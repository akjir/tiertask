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

import '../services/app_logger.dart';
import 'task_board.dart';
import 'task_item.dart';
import 'tdf_error.dart';
import 'tdf_location.dart';
import 'tdf_metadata.dart';
import 'tdf_payload_comparison.dart';
import 'tdf_sync_metadata.dart';
import 'tdf_timezone.dart';

/// Result of reconciling `label` blocks and label deletion records.
@immutable
class LabelReconciliationOutcome {
  /// Creates a [LabelReconciliationOutcome].
  const LabelReconciliationOutcome({
    required this.liveLabels,
    required this.deletedLabelsById,
    required this.conflictedIds,
    required this.ambiguousIds,
    required this.retiredByUndelete,
    this.discardedIds = const <String>{},
    this.explicitlyDeletedIds = const <String>{},
  });

  /// Label IDs requiring user recovery after deletion history expiry.
  final List<String> ambiguousIds;

  /// Label IDs with unresolved deletion vs. modification conflicts.
  final List<String> conflictedIds;

  /// Active label deletion records keyed by label ID.
  final Map<String, TdfDeletedLabelRecord> deletedLabelsById;

  /// Stale-side label IDs discarded during generation refresh or explicit `discard` recovery.
  final Set<String> discardedIds;

  /// Label IDs resolved via explicit `Delete` during `DeletionConflict` resolution.
  final Set<String> explicitlyDeletedIds;

  /// Surviving reconciled live labels.
  final List<TdfLabel> liveLabels;

  /// Whether at least one deletion record was retired by an explicit undelete resolution.
  final bool retiredByUndelete;
}

/// Result of reconciling `location` blocks and location deletion records.
@immutable
class LocationReconciliationOutcome {
  /// Creates a [LocationReconciliationOutcome].
  const LocationReconciliationOutcome({
    required this.liveLocations,
    required this.deletedLocationsById,
    required this.conflictedIds,
    required this.ambiguousIds,
    required this.retiredByUndelete,
    this.discardedIds = const <String>{},
    this.explicitlyDeletedIds = const <String>{},
  });

  /// Location IDs requiring user recovery after deletion history expiry.
  final List<String> ambiguousIds;

  /// Location IDs with unresolved deletion vs. modification conflicts.
  final List<String> conflictedIds;

  /// Active location deletion records keyed by location ID.
  final Map<String, TdfDeletedLocationRecord> deletedLocationsById;

  /// Stale-side location IDs discarded during generation refresh or explicit `discard` recovery.
  final Set<String> discardedIds;

  /// Location IDs resolved via explicit `Delete` during `DeletionConflict` resolution.
  final Set<String> explicitlyDeletedIds;

  /// Surviving reconciled live locations.
  final List<TdfLocation> liveLocations;

  /// Whether at least one deletion record was retired by an explicit undelete resolution.
  final bool retiredByUndelete;
}

/// Stateless per-entity three-way location, label, and task reconciliation engine for `TaskBoardSync`.
@immutable
class TaskBoardReconciler {
  /// Prevents instantiation of this stateless helper class.
  const TaskBoardReconciler._();

  /// Throws a [TdfSyncOutcomeException] when [locations], [labels], or [tasks] recorded deletion conflicts or ambiguous recovery items.
  static void checkSyncOutcomes(
    LabelReconciliationOutcome labels,
    TaskReconciliationOutcome tasks, [
    LocationReconciliationOutcome? locations,
  ]) {
    final locConflicts = locations?.conflictedIds ?? const <String>[];
    final locAmbiguous = locations?.ambiguousIds ?? const <String>[];
    if (tasks.conflictedIds.isNotEmpty ||
        labels.conflictedIds.isNotEmpty ||
        locConflicts.isNotEmpty) {
      AppLogger.event(
        LogLevel.warn,
        LogTag.sync,
        'sync.conflict',
        fields: <String, Object?>{
          'kind': 'deletion_conflict',
          'tasks': tasks.conflictedIds.length,
          'labels': labels.conflictedIds.length,
          'locations': locConflicts.length,
        },
      );
      throw TdfSyncOutcomeException(
        kind: TdfSyncOutcomeKind.deletionConflict,
        conflictedTaskIds: List<String>.unmodifiable(tasks.conflictedIds),
        conflictedLabelIds: List<String>.unmodifiable(labels.conflictedIds),
        conflictedLocationIds: List<String>.unmodifiable(locConflicts),
        message: 'Entity deletion conflicts with concurrent live modification.',
      );
    }
    if (tasks.ambiguousIds.isNotEmpty ||
        labels.ambiguousIds.isNotEmpty ||
        locAmbiguous.isNotEmpty) {
      AppLogger.event(
        LogLevel.warn,
        LogTag.sync,
        'sync.conflict',
        fields: <String, Object?>{
          'kind': 'recovery_required',
          'tasks': tasks.ambiguousIds.length,
          'labels': labels.ambiguousIds.length,
          'locations': locAmbiguous.length,
        },
      );
      throw TdfSyncOutcomeException(
        kind: TdfSyncOutcomeKind.recoveryRequired,
        ambiguousTaskIds: List<String>.unmodifiable(tasks.ambiguousIds),
        ambiguousLabelIds: List<String>.unmodifiable(labels.ambiguousIds),
        ambiguousLocationIds: List<String>.unmodifiable(locAmbiguous),
        message: 'Ambiguous entities require user recovery after deletion history expiry.',
      );
    }
  }

  /// Computes label IDs resolved for explicit `Delete` or recovery `discard` so they do not trigger newly-introduced location reference conflicts (`TDF-DEL-002`).
  static Set<String> computeExplicitlyDeletedLabelIds(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    Map<String, TdfDeletedLabelRecord> initialDeletedLabels,
    (int?, bool, DateTime) options, {
    Map<String, TdfDeletionResolution> resolutions = const {},
    Map<String, TdfBoundDeletionDecision> boundDecisions = const {},
    Map<String, TdfRecoveryResolution> recoveryResolutions = const {},
    Set<String> freshlyRecoveredIds = const <String>{},
  }) {
    final (primary, secondary, baseline) = boards;
    final primaryMap = _indexById(primary.labels, (label) => label.id);
    final secondaryMap = _indexById(secondary.labels, (label) => label.id);
    final baselineMap = baseline != null
        ? _indexById(baseline.labels, (label) => label.id)
        : null;
    final context = _reconcileContext(boards, options);
    final allIds = <String>{...primaryMap.keys, ...secondaryMap.keys};
    final result = <String>{};
    for (final id in allIds) {
      if (_isLabelExplicitlyDeletedOrDiscarded(
        id: id,
        primaryLabel: primaryMap[id],
        secondaryLabel: secondaryMap[id],
        baselineLabel: baselineMap?[id],
        initialDeleted: initialDeletedLabels,
        context: context,
        resolutions: resolutions,
        boundDecisions: boundDecisions,
        recoveryResolutions: recoveryResolutions,
        freshlyRecoveredIds: freshlyRecoveredIds,
      )) {
        result.add(id);
      }
    }
    return result;
  }

  /// Computes task IDs resolved for explicit `Delete` or recovery `discard` so they do not trigger newly-introduced label or location reference conflicts (`TDF-DEL-002`).
  static Set<String> computeExplicitlyDeletedTaskIds(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    Map<String, TdfDeletedTaskRecord> initialDeletedTasks,
    (int?, bool, DateTime) options, {
    Map<String, TdfDeletionResolution> resolutions = const {},
    Map<String, TdfBoundDeletionDecision> boundDecisions = const {},
    Map<String, TdfRecoveryResolution> recoveryResolutions = const {},
    Set<String> freshlyRecoveredIds = const <String>{},
  }) {
    final (primary, secondary, baseline) = boards;
    final primaryMap = _indexById(primary.allTasks, (task) => task.id);
    final secondaryMap = _indexById(secondary.allTasks, (task) => task.id);
    final baselineMap = baseline != null
        ? _indexById(baseline.allTasks, (task) => task.id)
        : null;
    final context = _reconcileContext(boards, options);
    final allIds = <String>{...primaryMap.keys, ...secondaryMap.keys};
    final result = <String>{};
    for (final id in allIds) {
      if (_isTaskExplicitlyDeletedOrDiscarded(
        id: id,
        primaryTask: primaryMap[id],
        secondaryTask: secondaryMap[id],
        baselineTask: baselineMap?[id],
        initialDeleted: initialDeletedTasks,
        context: context,
        resolutions: resolutions,
        boundDecisions: boundDecisions,
        recoveryResolutions: recoveryResolutions,
        freshlyRecoveredIds: freshlyRecoveredIds,
      )) {
        result.add(id);
      }
    }
    return result;
  }

  /// Computes newly introduced label references $A_L(T) \cup A_R(T)$ across live and conflict-retained tasks (`TDF-DEL-002`).
  static Set<String> computeNewlyReferencedLabelIds(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    Map<String, TdfDeletedTaskRecord> initialDeletedTasks, {
    Set<String> explicitlyDeletedTaskIds = const <String>{},
  }) {
    final (primary, secondary, baseline) = boards;
    if (baseline == null) {
      return const <String>{};
    }
    final baseTaskMap = _indexById(baseline.allTasks, (task) => task.id);
    final newlyReferenced = <String>{};
    for (final task in <TaskItem>[...primary.allTasks, ...secondary.allTasks]) {
      if (explicitlyDeletedTaskIds.contains(task.id)) {
        continue;
      }
      final baseTask = baseTaskMap[task.id];
      if (baseTask != null) {
        _collectAddedStrings(task.labelIds, baseTask.labelIds, newlyReferenced);
      } else {
        newlyReferenced.addAll(task.labelIds);
      }
    }
    return newlyReferenced;
  }

  /// Computes newly introduced location references $A^{\text{loc}}_L(E) \cup A^{\text{loc}}_R(E)$ across live and conflict-retained tasks and labels (`TDF-DEL-002`).
  static Set<String> computeNewlyReferencedLocationIds(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    Map<String, TdfDeletedTaskRecord> initialDeletedTasks,
    Map<String, TdfDeletedLabelRecord> initialDeletedLabels, {
    Set<String> explicitlyDeletedTaskIds = const <String>{},
    Set<String> explicitlyDeletedLabelIds = const <String>{},
  }) {
    final (primary, secondary, baseline) = boards;
    if (baseline == null) {
      return const <String>{};
    }
    final baseTaskMap = _indexById(baseline.allTasks, (task) => task.id);
    final baseLabelMap = _indexById(baseline.labels, (label) => label.id);
    final newlyReferenced = <String>{};

    for (final task in <TaskItem>[...primary.allTasks, ...secondary.allTasks]) {
      if (explicitlyDeletedTaskIds.contains(task.id)) {
        continue;
      }
      final taskLocs = _extractLocationIds(task.conditions);
      final baseTask = baseTaskMap[task.id];
      if (baseTask != null) {
        final baseLocs = _extractLocationIds(baseTask.conditions);
        _collectAddedStrings(taskLocs, baseLocs, newlyReferenced);
      } else {
        newlyReferenced.addAll(taskLocs);
      }
    }
    for (final label in <TdfLabel>[...primary.labels, ...secondary.labels]) {
      if (explicitlyDeletedLabelIds.contains(label.id)) {
        continue;
      }
      final labelLocs = _extractLocationIds(label.conditions);
      final baseLabel = baseLabelMap[label.id];
      if (baseLabel != null) {
        final baseLocs = _extractLocationIds(baseLabel.conditions);
        _collectAddedStrings(labelLocs, baseLocs, newlyReferenced);
      } else {
        newlyReferenced.addAll(labelLocs);
      }
    }
    return newlyReferenced;
  }

  /// Reconciles all `label` blocks across [boards], [initialDeleted], [resolutions], and [options].
  static LabelReconciliationOutcome reconcileLabels(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    Map<String, TdfDeletedLabelRecord> initialDeleted,
    Map<String, TdfDeletionResolution> resolutions,
    (int?, bool, DateTime) options, {
    Map<String, TdfBoundDeletionDecision> boundDecisions = const {},
    Map<String, TdfRecoveryResolution> recoveryResolutions = const {},
    Set<String> freshlyRecoveredIds = const <String>{},
    Set<String> tombstonedLocationIds = const <String>{},
    Set<String> newlyReferencedLabelIds = const <String>{},
  }) {
    final (primary, secondary, baseline) = boards;
    final primaryMap = _indexById(primary.labels, (label) => label.id);
    final secondaryMap = _indexById(secondary.labels, (label) => label.id);
    final baselineMap = baseline != null
        ? _indexById(baseline.labels, (label) => label.id)
        : null;
    final context = _reconcileContext(boards, options);
    final accumulator = (
      live: <TdfLabel>[],
      deleted: <String, TdfDeletedLabelRecord>{...initialDeleted},
      conflicted: <String>[],
      ambiguous: <String>[],
      discarded: <String>{},
      explicitlyDeleted: <String>{},
    );
    var retired = false;
    for (final id in <String>{...primaryMap.keys, ...secondaryMap.keys}) {
      final pair = (primaryMap[id], secondaryMap[id], baselineMap?[id]);
      if (_reconcileSingleLabel(
        id,
        pair,
        context,
        accumulator,
        resolutions: resolutions,
        boundDecisions: boundDecisions,
        recoveryResolutions: recoveryResolutions,
        freshlyRecoveredIds: freshlyRecoveredIds,
        tombstonedLocationIds: tombstonedLocationIds,
        newlyReferencedLabelIds: newlyReferencedLabelIds,
      )) {
        retired = true;
      }
    }
    return LabelReconciliationOutcome(
      liveLabels: accumulator.live,
      deletedLabelsById: accumulator.deleted,
      conflictedIds: accumulator.conflicted,
      ambiguousIds: accumulator.ambiguous,
      retiredByUndelete: retired,
      discardedIds: accumulator.discarded,
      explicitlyDeletedIds: accumulator.explicitlyDeleted,
    );
  }

  /// Reconciles all `location` blocks across [boards], [initialDeleted], [resolutions], and [options].
  static LocationReconciliationOutcome reconcileLocations(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    Map<String, TdfDeletedLocationRecord> initialDeleted,
    Map<String, TdfDeletionResolution> resolutions,
    (int?, bool, DateTime) options, {
    Map<String, TdfBoundDeletionDecision> boundDecisions = const {},
    Map<String, TdfRecoveryResolution> recoveryResolutions = const {},
    Set<String> freshlyRecoveredIds = const <String>{},
    Set<String> newlyReferencedLocationIds = const <String>{},
  }) {
    final (primary, secondary, baseline) = boards;
    final primaryMap = _indexById(primary.locations, (location) => location.id);
    final secondaryMap = _indexById(
      secondary.locations,
      (location) => location.id,
    );
    final baselineMap = baseline != null
        ? _indexById(baseline.locations, (location) => location.id)
        : null;
    final context = _reconcileContext(boards, options);
    final accumulator = (
      live: <TdfLocation>[],
      deleted: <String, TdfDeletedLocationRecord>{...initialDeleted},
      conflicted: <String>[],
      ambiguous: <String>[],
      discarded: <String>{},
      explicitlyDeleted: <String>{},
    );
    var retired = false;
    for (final id in <String>{...primaryMap.keys, ...secondaryMap.keys}) {
      final pair = (primaryMap[id], secondaryMap[id], baselineMap?[id]);
      if (_reconcileSingleLocation(
        id,
        pair,
        context,
        accumulator,
        resolutions: resolutions,
        boundDecisions: boundDecisions,
        recoveryResolutions: recoveryResolutions,
        freshlyRecoveredIds: freshlyRecoveredIds,
        newlyReferencedLocationIds: newlyReferencedLocationIds,
      )) {
        retired = true;
      }
    }
    return LocationReconciliationOutcome(
      liveLocations: accumulator.live,
      deletedLocationsById: accumulator.deleted,
      conflictedIds: accumulator.conflicted,
      ambiguousIds: accumulator.ambiguous,
      retiredByUndelete: retired,
      discardedIds: accumulator.discarded,
      explicitlyDeletedIds: accumulator.explicitlyDeleted,
    );
  }

  /// Reconciles all `task` blocks across [boards], [initialDeleted], [resolutions], and [options].
  static TaskReconciliationOutcome reconcileTasks(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    Map<String, TdfDeletedTaskRecord> initialDeleted,
    Map<String, TdfDeletionResolution> resolutions,
    (int?, bool, DateTime) options, {
    Map<String, TdfBoundDeletionDecision> boundDecisions = const {},
    Map<String, TdfRecoveryResolution> recoveryResolutions = const {},
    Set<String> freshlyRecoveredIds = const <String>{},
    Set<String> tombstonedLocationIds = const <String>{},
    Set<String> deletedLabelsLocal = const <String>{},
    Set<String> deletedLabelsIncoming = const <String>{},
    Set<String>? validLabelIds,
    Map<String, TdfLabel> postCascadeLabelsById = const <String, TdfLabel>{},
    TdfCleanupMode cleanupMode = TdfCleanupMode.finalStage,
  }) {
    final (primary, secondary, baseline) = boards;
    final primaryMap = _indexById(primary.allTasks, (task) => task.id);
    final secondaryMap = _indexById(secondary.allTasks, (task) => task.id);
    final baselineMap = baseline != null
        ? _indexById(baseline.allTasks, (task) => task.id)
        : null;
    final context = _reconcileContext(boards, options);
    final allTaskIds = <String>{...primaryMap.keys, ...secondaryMap.keys};
    final previewContext = _buildPreviewPrerequisiteContext(
      allTaskIds: allTaskIds,
      primaryMap: primaryMap,
      secondaryMap: secondaryMap,
      baselineMap: baselineMap,
      initialDeleted: initialDeleted,
      context: context,
      resolutions: resolutions,
      boundDecisions: boundDecisions,
      recoveryResolutions: recoveryResolutions,
      freshlyRecoveredIds: freshlyRecoveredIds,
    );

    final accumulator = (
      live: <TaskItem>[],
      uncleanedById: <String, TaskItem>{},
      undeletedIds: <String>{},
      discardedIds: <String>{},
      explicitlyDeletedIds: <String>{},
      deleted: <String, TdfDeletedTaskRecord>{...initialDeleted},
      conflicted: <String>[],
      ambiguous: <String>[],
    );
    var retired = false;

    for (final id in allTaskIds) {
      final primaryTask = primaryMap[id];
      final secondaryTask = secondaryMap[id];
      if (primaryTask != null && secondaryTask != null) {
        continue;
      }
      if (_reconcileOneSidedTask(
        id,
        (primaryTask, secondaryTask, baselineMap?[id]),
        context,
        accumulator,
        resolutions: resolutions,
        boundDecisions: boundDecisions,
        recoveryResolutions: recoveryResolutions,
        freshlyRecoveredIds: freshlyRecoveredIds,
        previewLiveTasksById: previewContext.liveById,
        previewDeletedTaskIds: previewContext.deletedIds,
      )) {
        retired = true;
      }
    }

    final mergedHeadersById = <String, TaskItem>{
      for (final task in accumulator.live) task.id: task,
      ...previewContext.twoSidedHeadersById,
    };
    final mergedDeletedTaskIds = <String>{
      ...accumulator.deleted.keys,
      ...accumulator.discardedIds,
    };
    final orderedLive = <TaskItem>[];
    final oneSidedById = _indexById(accumulator.live, (task) => task.id);
    final logDebug = AppLogger.shouldLog(LogLevel.debug);
    final debugEntries = logDebug
        ? <({String event, Map<String, Object?> fields})>[]
        : null;
    var unchangedTwoSidedCount = 0;
    var reconciledTwoSidedCount = 0;

    for (final id in allTaskIds) {
      final primaryTask = primaryMap[id];
      final secondaryTask = secondaryMap[id];
      if (primaryTask != null && secondaryTask != null) {
        final step = _reconcileTwoSidedTask(
          id: id,
          local: primaryTask,
          incoming: secondaryTask,
          baseline: baselineMap?[id],
          now: context.now,
          cleanupMode: cleanupMode,
          mergedLiveTasksById: mergedHeadersById,
          mergedDeletedTaskIds: mergedDeletedTaskIds,
          tombstonedLocationIds: tombstonedLocationIds,
          deletedLabelsLocal: deletedLabelsLocal,
          deletedLabelsIncoming: deletedLabelsIncoming,
          validLabelIds: validLabelIds,
          postCascadeLabelsById: postCascadeLabelsById,
          uncleanedOut: accumulator.uncleanedById,
          debugEntriesOut: debugEntries,
        );
        orderedLive.add(step.task);
        if (step.wasUnchanged) {
          unchangedTwoSidedCount++;
        } else {
          reconciledTwoSidedCount++;
        }
      } else if (oneSidedById[id] case final oneSided?) {
        orderedLive.add(oneSided);
      }
    }

    if (debugEntries != null &&
        (unchangedTwoSidedCount > 0 || reconciledTwoSidedCount > 0)) {
      debugEntries.add((
        event: 'sync.reconcile.summary',
        fields: <String, Object?>{
          'total': unchangedTwoSidedCount + reconciledTwoSidedCount,
          'unchanged': unchangedTwoSidedCount,
          'reconciled': reconciledTwoSidedCount,
        },
      ));
      AppLogger.eventBatch(LogLevel.debug, LogTag.sync, debugEntries);
    }

    return TaskReconciliationOutcome(
      liveTasks: orderedLive,
      deletedTasksById: accumulator.deleted,
      conflictedIds: accumulator.conflicted,
      ambiguousIds: accumulator.ambiguous,
      retiredByUndelete: retired,
      uncleanedLiveTasksById: accumulator.uncleanedById,
      undeletedTaskIds: accumulator.undeletedIds,
      discardedTaskIds: accumulator.discardedIds,
      explicitlyDeletedTaskIds: accumulator.explicitlyDeletedIds,
    );
  }

  /// Computes symmetric Phase 1 generation refresh flags `(primaryRefresh, secondaryRefresh)` (`TDF-REC-001`).
  static ({bool primaryRefresh, bool secondaryRefresh})
  resolveGenerationRefreshFlags(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    int? effectiveAckGen,
    bool requireAcknowledgedGeneration,
  ) {
    final (primary, secondary, _) = boards;
    final leftGen = primary.deletedBlock.generation;
    final rightGen = secondary.deletedBlock.generation;
    final primaryRefresh =
        (effectiveAckGen != null && rightGen > effectiveAckGen) ||
        rightGen > leftGen ||
        (effectiveAckGen == null &&
            (requireAcknowledgedGeneration || rightGen > 0));
    final secondaryRefresh = leftGen > rightGen;
    return (primaryRefresh: primaryRefresh, secondaryRefresh: secondaryRefresh);
  }

  /// Strips deleted or discarded labels from [tasks], applies `TDF-MERGE-011` `scoped` flood protection, and validates remaining label references.
  static List<TaskItem> stripDeletedLabelsAndValidateReferences(
    List<TaskItem> tasks,
    Set<String> validIds,
    Map<String, TdfDeletedLabelRecord> deletedById,
    List<TdfLabel>? baselineLabels, {
    Set<String> discardedLabelIds = const <String>{},
    Set<String> explicitlyDeletedLabelIds = const <String>{},
    Set<String> knownScopedLabelIds = const <String>{},
    Set<String>? evictedFromQueueOut,
    (TaskBoard, TaskBoard, TaskBoard?)? boards,
    Set<String>? mutatedByNowCascadeOut,
    DateTime? now,
  }) {
    final baseIds = <String>{
      if (baselineLabels != null)
        for (final label in baselineLabels) label.id,
    };
    final scopedIds = <String>{
      ...knownScopedLabelIds,
      if (baselineLabels != null)
        for (final label in baselineLabels)
          if (label.isScoped && !validIds.contains(label.id)) label.id,
    };
    final primaryMap = boards != null
        ? _indexById(boards.$1.allTasks, (task) => task.id)
        : const <String, TaskItem>{};
    final secondaryMap = boards != null
        ? _indexById(boards.$2.allTasks, (task) => task.id)
        : const <String, TaskItem>{};
    final baselineMap = boards?.$3 != null
        ? _indexById(
            boards?.$3?.allTasks ?? const <TaskItem>[],
            (task) => task.id,
          )
        : const <String, TaskItem>{};
    final alreadyQueuedUnlabelled = boards != null
        ? _computeAlreadyQueuedUnlabelledTaskIds(
            boards.$1,
            boards.$2,
            primaryMap,
            secondaryMap,
          )
        : const <String>{};
    return <TaskItem>[
      for (final task in tasks)
        _stripDeletedLabelsFromSingleTask(
          task,
          validIds,
          deletedById,
          baseIds,
          discardedLabelIds: discardedLabelIds,
          explicitlyDeletedLabelIds: explicitlyDeletedLabelIds,
          scopedLabelSet: scopedIds,
          alreadyQueuedUnlabelledTaskIds: alreadyQueuedUnlabelled,
          evictedFromQueueOut: evictedFromQueueOut,
          sourceVariants: (
            primaryMap[task.id],
            secondaryMap[task.id],
            baselineMap[task.id],
          ),
          mutatedByNowCascadeOut: mutatedByNowCascadeOut,
          now: now,
        ),
    ];
  }

  /// Strips deleted or discarded locations from [labels], updates revisions (`TDF-MERGE-004` / `TDF-DEL-003`), and validates remaining location references.
  static List<TdfLabel> stripDeletedLocationsFromLabelsAndValidate(
    List<TdfLabel> labels,
    Set<String> validLocationIds,
    Map<String, TdfDeletedLocationRecord> deletedLocationsById,
    List<TdfLocation>? baselineLocations, {
    Set<String> discardedLocationIds = const <String>{},
    Set<String> explicitlyDeletedLocationIds = const <String>{},
    (TaskBoard, TaskBoard, TaskBoard?)? boards,
    DateTime? now,
  }) {
    final baseIds = <String>{
      if (baselineLocations != null)
        for (final location in baselineLocations) location.id,
    };
    final primaryMap = boards != null
        ? _indexById(boards.$1.labels, (label) => label.id)
        : const <String, TdfLabel>{};
    final secondaryMap = boards != null
        ? _indexById(boards.$2.labels, (label) => label.id)
        : const <String, TdfLabel>{};
    final baselineMap = boards?.$3 != null
        ? _indexById(
            boards?.$3?.labels ?? const <TdfLabel>[],
            (label) => label.id,
          )
        : const <String, TdfLabel>{};
    return <TdfLabel>[
      for (final label in labels)
        _stripDeletedLocationsFromSingleLabel(
          label,
          validLocationIds,
          deletedLocationsById,
          baseIds,
          discardedLocationIds: discardedLocationIds,
          explicitlyDeletedLocationIds: explicitlyDeletedLocationIds,
          sourceVariants: (
            primaryMap[label.id],
            secondaryMap[label.id],
            baselineMap[label.id],
          ),
          now: now,
        ),
    ];
  }

  /// Strips deleted or discarded locations from [tasks] (inserting `condition location any` when a live assigned label still carries a location rule) and validates remaining location references.
  static List<TaskItem> stripDeletedLocationsFromTasksAndValidate(
    List<TaskItem> tasks,
    Set<String> validLocationIds,
    Map<String, TdfDeletedLocationRecord> deletedLocationsById,
    List<TdfLocation>? baselineLocations,
    Map<String, TdfLabel> postCascadeLabelsById, {
    Set<String> discardedLocationIds = const <String>{},
    Set<String> explicitlyDeletedLocationIds = const <String>{},
    Set<String>? mutatedByNowCascadeOut,
    DateTime? now,
  }) {
    final baseIds = <String>{
      if (baselineLocations != null)
        for (final location in baselineLocations) location.id,
    };
    return <TaskItem>[
      for (final task in tasks)
        _stripDeletedLocationsFromSingleTask(
          task,
          validLocationIds,
          deletedLocationsById,
          baseIds,
          postCascadeLabelsById,
          discardedLocationIds: discardedLocationIds,
          explicitlyDeletedLocationIds: explicitlyDeletedLocationIds,
          mutatedByNowCascadeOut: mutatedByNowCascadeOut,
          now: now,
        ),
    ];
  }

  /// Verifies asymmetric `secondary.deleted.generation >= effectiveAckGen` (`TDF-REC-001`) and completion-counter monotonicity (`TDF-MERGE-010`).
  static void verifyGenerationsAndCompletionHistory(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    int? effectiveAckGen,
  ) {
    final (primary, secondary, baseline) = boards;
    final rightGen = secondary.deletedBlock.generation;
    if (effectiveAckGen != null && rightGen < effectiveAckGen) {
      throw const TdfSyncOutcomeException(
        kind: TdfSyncOutcomeKind.syncGenerationRollback,
        message: 'Shared deletion history generation is lower than the acknowledged generation.',
      );
    }
    if (baseline == null) {
      return;
    }
    final primaryMap = _indexById(primary.allTasks, (task) => task.id);
    final secondaryMap = _indexById(secondary.allTasks, (task) => task.id);
    final regressedIds = <String>[];
    for (final baseTask in baseline.allTasks) {
      final primaryTask = primaryMap[baseTask.id];
      final secondaryTask = secondaryMap[baseTask.id];
      if ((primaryTask != null &&
              primaryTask.completions < baseTask.completions) ||
          (secondaryTask != null &&
              secondaryTask.completions < baseTask.completions)) {
        regressedIds.add(baseTask.id);
      }
    }
    if (regressedIds.isNotEmpty) {
      throw TdfSyncOutcomeException(
        kind: TdfSyncOutcomeKind.recoveryRequired,
        ambiguousTaskIds: List<String>.unmodifiable(regressedIds),
        message: 'Task completion counter regressed below the proven baseline counter.',
      );
    }
  }

  /// Builds preview live task headers and non-conflicting deleted/retired task IDs for `TDF-DEL-002` and `TDF-REC-001` baseline hygiene.
  static ({
    Map<String, TaskItem> liveById,
    Map<String, TaskItem> twoSidedHeadersById,
    Set<String> deletedIds,
  })
  _buildPreviewPrerequisiteContext({
    required Set<String> allTaskIds,
    required Map<String, TaskItem> primaryMap,
    required Map<String, TaskItem> secondaryMap,
    required Map<String, TaskItem>? baselineMap,
    required Map<String, TdfDeletedTaskRecord> initialDeleted,
    required _ReconcileContext context,
    required Map<String, TdfDeletionResolution> resolutions,
    required Map<String, TdfBoundDeletionDecision> boundDecisions,
    required Map<String, TdfRecoveryResolution> recoveryResolutions,
    required Set<String> freshlyRecoveredIds,
  }) {
    final liveById = <String, TaskItem>{};
    final twoSidedHeadersById = <String, TaskItem>{};
    final deletedIds = <String>{
      for (final id in initialDeleted.keys)
        if (!allTaskIds.contains(id)) id,
    };
    var pendingCandidates = <_PreviewDeleteCandidate>[];

    for (final id in allTaskIds) {
      _processSinglePreviewTask(
        id: id,
        primaryTask: primaryMap[id],
        secondaryTask: secondaryMap[id],
        baselineTask: baselineMap?[id],
        initialDeleted: initialDeleted,
        context: context,
        resolutions: resolutions,
        boundDecisions: boundDecisions,
        recoveryResolutions: recoveryResolutions,
        freshlyRecoveredIds: freshlyRecoveredIds,
        liveById: liveById,
        twoSidedHeadersById: twoSidedHeadersById,
        deletedIds: deletedIds,
        pendingCandidates: pendingCandidates,
      );
    }

    while (pendingCandidates.isNotEmpty) {
      final pass = _promoteUnchangedPreviewCandidates(
        pendingCandidates,
        liveById: liveById,
        deletedIds: deletedIds,
        nowUtc: context.now,
      );
      if (!pass.promotedAny) {
        break;
      }
      pendingCandidates = pass.remaining;
    }

    return (
      liveById: liveById,
      twoSidedHeadersById: twoSidedHeadersById,
      deletedIds: deletedIds,
    );
  }

  /// Appends elements in [current] that are absent from [baseline] into [target].
  static void _collectAddedStrings(
    Iterable<String> current,
    List<String> baseline,
    Set<String> target,
  ) {
    for (final id in current) {
      if (!baseline.contains(id)) {
        target.add(id);
      }
    }
  }

  /// Returns task IDs already listed in `queue` with `labelIds.isEmpty` on either [primary] or [secondary] (`TDF-MERGE-011` Point 1).
  static Set<String> _computeAlreadyQueuedUnlabelledTaskIds(
    TaskBoard primary,
    TaskBoard secondary,
    Map<String, TaskItem> primaryMap,
    Map<String, TaskItem> secondaryMap,
  ) {
    final result = <String>{};
    for (final id in primary.queueBlock.taskIds) {
      final task = primaryMap[id];
      if (task != null && task.labelIds.isEmpty) {
        result.add(id);
      }
    }
    for (final id in secondary.queueBlock.taskIds) {
      final task = secondaryMap[id];
      if (task != null && task.labelIds.isEmpty) {
        result.add(id);
      }
    }
    return result;
  }

  /// Computes `decisionRevision = max(now, eachObservedRevision + 1 second)` (`TDF-DEL-003`).
  static DateTime _computeDecisionRevision(
    (DateTime, DateTime, DateTime?) revisions,
    DateTime now,
  ) {
    final (liveRev, deletedRev, baseRev) = revisions;
    var maxObserved = liveRev.isAfter(deletedRev) ? liveRev : deletedRev;
    if (baseRev != null && baseRev.isAfter(maxObserved)) {
      maxObserved = baseRev;
    }
    final bumped = maxObserved.add(const Duration(seconds: 1));
    final decision = now.isAfter(bumped) ? now : bumped;
    if (!TdfCalendar.isWithinTimestampBounds(decision)) {
      throw const TdfException(
        kind: TdfErrorKind.invalidTimestamp,
        line: 1,
        message: 'Decision revision exceeds maximum supported timestamp.',
      );
    }
    return decision;
  }

  /// Extracts all referenced `<location-id>` tokens from [conditions].
  static List<String> _extractLocationIds(List<TaskCondition> conditions) {
    final ids = <String>[];
    for (final rule in conditions) {
      if (rule is LocationTaskCondition && rule.locationIds.isNotEmpty) {
        ids.addAll(rule.locationIds);
      }
    }
    return ids;
  }

  /// Filters [locationIds] against [validLocationIds], [deletedLocationsById], [baselineLocationSet], and [discardedLocationIds].
  static ({List<String> retainedIds, bool strippedAny, bool strippedByMutation})
  _filterLocationIdsForEntity({
    required String entityKind,
    required String entityId,
    required List<String> locationIds,
    required Set<String> validLocationIds,
    required Map<String, TdfDeletedLocationRecord> deletedLocationsById,
    required Set<String> baselineLocationSet,
    required Set<String> discardedLocationIds,
    required Set<String> explicitlyDeletedLocationIds,
  }) {
    final retained = <String>[];
    var stripped = false;
    var byMutation = false;

    for (final locationId in locationIds) {
      if (validLocationIds.contains(locationId)) {
        retained.add(locationId);
        continue;
      }
      final deletedRecord = deletedLocationsById[locationId];
      if (deletedRecord != null ||
          baselineLocationSet.contains(locationId) ||
          discardedLocationIds.contains(locationId)) {
        stripped = true;
        if (explicitlyDeletedLocationIds.contains(locationId) ||
            discardedLocationIds.contains(locationId)) {
          byMutation = true;
        }
        continue;
      }
      throw TdfException(
        kind: TdfErrorKind.unknownLocationReference,
        line: 1,
        message:
            'Merged $entityKind "$entityId" references undeclared location "$locationId".',
      );
    }
    return (
      retainedIds: retained,
      strippedAny: stripped,
      strippedByMutation: byMutation,
    );
  }

  /// Computes the post-cascade [TaskItem] and its deterministic `TDF-MERGE-004` / `TDF-DEL-003` revision after stripping deleted labels.
  static TaskItem _finalizePostLabelCascadeTask(
    TaskItem task, {
    required List<String> retained,
    required bool nextPriority,
    required bool strippedByMutation,
    required (TaskItem?, TaskItem?, TaskItem?) sourceVariants,
    required DateTime? now,
  }) {
    final candidate = task.copyWith(
      labelIds: retained,
      isPriority: nextPriority,
    );
    if (strippedByMutation && now != null) {
      return candidate.copyWith(
        modifiedAt: TaskItem.nextModifiedTimestamp(
          now,
          task.effectiveModifiedAt,
        ),
      );
    }
    final (primaryTask, secondaryTask, baselineTask) = sourceVariants;
    if (primaryTask != null && secondaryTask != null) {
      var greatest =
          TdfPayloadComparison.compareTaskVersions(
                primaryTask,
                secondaryTask,
              ) >=
              0
          ? primaryTask
          : secondaryTask;
      if (baselineTask != null &&
          TdfPayloadComparison.compareTaskVersions(baselineTask, greatest) >
              0) {
        greatest = baselineTask;
      }
      if (greatest.completions == candidate.completions &&
          TdfPayloadComparison.compareTaskPayloads(greatest, candidate) == 0) {
        return candidate.copyWith(
          modifiedAt: greatest.modifiedAt,
          clearModifiedAt: greatest.modifiedAt == null,
        );
      }
      var maxObserved = _laterDate(
        primaryTask.effectiveModifiedAt,
        secondaryTask.effectiveModifiedAt,
      );
      maxObserved = _laterDate(maxObserved, baselineTask?.effectiveModifiedAt);
      return candidate.copyWith(
        modifiedAt: _validatedPlusOneSecond(maxObserved),
      );
    }
    return candidate.copyWith(
      modifiedAt: _validatedPlusOneSecond(task.effectiveModifiedAt),
    );
  }

  /// Computes the post-cascade [TdfLabel] and its deterministic `TDF-MERGE-004` / `TDF-DEL-003` revision after stripping deleted locations.
  static TdfLabel _finalizePostLocationCascadeLabel(
    TdfLabel label, {
    required List<TaskCondition> updatedConditions,
    required bool strippedByMutation,
    required (TdfLabel?, TdfLabel?, TdfLabel?) sourceVariants,
    required DateTime? now,
  }) {
    final candidate = label.copyWith(conditions: updatedConditions);
    if (strippedByMutation && now != null) {
      return candidate.copyWith(
        modifiedAt: TaskItem.nextModifiedTimestamp(
          now,
          label.effectiveModifiedAt,
        ),
      );
    }
    final (primaryLabel, secondaryLabel, baselineLabel) = sourceVariants;
    if (primaryLabel != null && secondaryLabel != null) {
      var greatest =
          TdfPayloadComparison.compareLabelVersions(
                primaryLabel,
                secondaryLabel,
              ) >=
              0
          ? primaryLabel
          : secondaryLabel;
      if (baselineLabel != null &&
          TdfPayloadComparison.compareLabelVersions(baselineLabel, greatest) >
              0) {
        greatest = baselineLabel;
      }
      if (TdfPayloadComparison.compareLabelPayloads(greatest, candidate) == 0) {
        return candidate.copyWith(
          modifiedAt: greatest.modifiedAt,
          clearModifiedAt: greatest.modifiedAt == null,
        );
      }
      var maxObserved = _laterDate(
        primaryLabel.effectiveModifiedAt,
        secondaryLabel.effectiveModifiedAt,
      );
      maxObserved = _laterDate(maxObserved, baselineLabel?.effectiveModifiedAt);
      return candidate.copyWith(
        modifiedAt: _validatedPlusOneSecond(maxObserved),
      );
    }
    final sourceLabel = primaryLabel ?? secondaryLabel;
    if (sourceLabel != null &&
        TdfPayloadComparison.compareLabelPayloads(sourceLabel, candidate) ==
            0) {
      return candidate.copyWith(
        modifiedAt: sourceLabel.modifiedAt,
        clearModifiedAt: sourceLabel.modifiedAt == null,
      );
    }
    final baseMod = (sourceLabel ?? label).effectiveModifiedAt;
    return candidate.copyWith(modifiedAt: _validatedPlusOneSecond(baseMod));
  }

  /// Returns whether any label in [labelIds] has a post-cascade `LocationTaskCondition` in [postCascadeLabelsById].
  static bool _hasLiveLabelLocationRule(
    List<String> labelIds,
    Map<String, TdfLabel> postCascadeLabelsById,
  ) {
    for (final labelId in labelIds) {
      final label = postCascadeLabelsById[labelId];
      if (label != null && _extractLocationIds(label.conditions).isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  /// Indexes [items] by the key returned from [idOf].
  static Map<String, T> _indexById<T>(
    Iterable<T> items,
    String Function(T item) idOf,
  ) => <String, T>{for (final item in items) idOf(item): item};

  /// Returns whether one-sided label [id] is resolved to explicit `Delete` or recovery `discard`.
  static bool _isLabelExplicitlyDeletedOrDiscarded({
    required String id,
    required TdfLabel? primaryLabel,
    required TdfLabel? secondaryLabel,
    required TdfLabel? baselineLabel,
    required Map<String, TdfDeletedLabelRecord> initialDeleted,
    required _ReconcileContext context,
    required Map<String, TdfDeletionResolution> resolutions,
    required Map<String, TdfBoundDeletionDecision> boundDecisions,
    required Map<String, TdfRecoveryResolution> recoveryResolutions,
    required Set<String> freshlyRecoveredIds,
  }) {
    if (primaryLabel != null && secondaryLabel != null) {
      return false;
    }
    final surviving = primaryLabel ?? secondaryLabel;
    if (surviving == null || freshlyRecoveredIds.contains(id)) {
      return false;
    }
    final isStale = primaryLabel != null
        ? context.primaryRefresh
        : context.secondaryRefresh;
    var record = initialDeleted[id];
    if (record == null && baselineLabel != null && !isStale) {
      final synthAt = TaskItem.nextModifiedTimestamp(
        context.now,
        baselineLabel.effectiveModifiedAt,
      );
      record = TdfDeletedLabelRecord(labelId: id, deletedAt: synthAt);
    }
    if (record != null) {
      return _resolveEffectiveLabelDecision(
            surviving,
            record,
            resolutions,
            boundDecisions,
          ) ==
          TdfDeletionResolution.delete;
    }
    return isStale && recoveryResolutions[id] == TdfRecoveryResolution.discard;
  }

  /// Returns whether [label] is identical to [baseLabel] in payload and effective revision.
  static bool _isLabelUnchangedFromBaseline(
    TdfLabel label,
    TdfLabel baseLabel,
  ) =>
      label.effectiveModifiedAt == baseLabel.effectiveModifiedAt &&
      TdfPayloadComparison.compareLabelPayloads(label, baseLabel) == 0;

  /// Returns whether [location] is identical to [baseLocation] in payload and effective revision.
  static bool _isLocationUnchangedFromBaseline(
    TdfLocation location,
    TdfLocation baseLocation,
  ) =>
      location.effectiveModifiedAt == baseLocation.effectiveModifiedAt &&
      TdfPayloadComparison.compareLocationPayloads(location, baseLocation) == 0;

  /// Returns whether one-sided task [id] is resolved to explicit `Delete` or recovery `discard`.
  static bool _isTaskExplicitlyDeletedOrDiscarded({
    required String id,
    required TaskItem? primaryTask,
    required TaskItem? secondaryTask,
    required TaskItem? baselineTask,
    required Map<String, TdfDeletedTaskRecord> initialDeleted,
    required _ReconcileContext context,
    required Map<String, TdfDeletionResolution> resolutions,
    required Map<String, TdfBoundDeletionDecision> boundDecisions,
    required Map<String, TdfRecoveryResolution> recoveryResolutions,
    required Set<String> freshlyRecoveredIds,
  }) {
    if (primaryTask != null && secondaryTask != null) {
      return false;
    }
    final surviving = primaryTask ?? secondaryTask;
    if (surviving == null || freshlyRecoveredIds.contains(id)) {
      return false;
    }
    final isStale = primaryTask != null
        ? context.primaryRefresh
        : context.secondaryRefresh;
    var record = initialDeleted[id];
    if (record == null && baselineTask != null && !isStale) {
      final synthAt = TaskItem.nextModifiedTimestamp(
        context.now,
        baselineTask.effectiveModifiedAt,
      );
      record = TdfDeletedTaskRecord(
        taskId: id,
        deletedAt: synthAt,
        completionsCheckpoint: baselineTask.completions,
      );
    }
    if (record != null) {
      return _resolveEffectiveTaskDecision(
            surviving,
            record,
            resolutions,
            boundDecisions,
          ) ==
          TdfDeletionResolution.delete;
    }
    return isStale && recoveryResolutions[id] == TdfRecoveryResolution.discard;
  }

  /// Returns whether [task] is unchanged relative to [baseTask] (ignoring `TDF-CLEAN-001` automatic block-cleanup-only changes).
  static bool _isTaskUnchangedFromBaseline(
    TaskItem task,
    TaskItem baseTask, {
    required Map<String, TaskItem> previewLiveTasksById,
    required Set<String> previewDeletedTaskIds,
    required DateTime nowUtc,
  }) {
    if (task.completions != baseTask.completions) {
      return false;
    }
    if (TdfPayloadComparison.taskPayloadsEqual(task, baseTask)) {
      return task.effectiveModifiedAt == baseTask.effectiveModifiedAt;
    }
    final bothOpen =
        !task.isCompleted &&
        task.completedAt == null &&
        !baseTask.isCompleted &&
        baseTask.completedAt == null;
    if (!bothOpen) {
      return false;
    }
    return TdfPayloadComparison.taskPayloadsEqualModuloBlockCleanup(
      left: task,
      right: baseTask,
      liveTasksById: previewLiveTasksById,
      deletedTaskIds: previewDeletedTaskIds,
      nowUtc: nowUtc,
    );
  }

  /// Returns the later of [left] and optional [right].
  static DateTime _laterDate(DateTime left, DateTime? right) =>
      (right != null && right.isAfter(left)) ? right : left;

  /// Verifies whether [bound] matches [surviving] and [deletedRecord] (`TDF-DEL-003`).
  static bool _matchesBoundLabelDecision(
    TdfBoundDeletionDecision bound,
    TdfLabel surviving,
    TdfDeletedLabelRecord deletedRecord,
  ) {
    if (bound.expectedLiveModifiedAt case final expectedMod?
        when TaskItem.normalizeTimestamp(expectedMod) !=
            surviving.effectiveModifiedAt) {
      return false;
    }
    if (bound.expectedDeletionAt case final expectedDel?
        when TaskItem.normalizeTimestamp(expectedDel) !=
            deletedRecord.deletedAt) {
      return false;
    }
    if (bound.expectedLivePayloadSignature case final expectedSig?
        when expectedSig !=
            TdfPayloadComparison.labelPayloadSignature(surviving)) {
      return false;
    }
    return true;
  }

  /// Verifies whether [bound] matches [surviving] and [deletedRecord] (`TDF-DEL-003`).
  static bool _matchesBoundLocationDecision(
    TdfBoundDeletionDecision bound,
    TdfLocation surviving,
    TdfDeletedLocationRecord deletedRecord,
  ) {
    if (bound.expectedLiveModifiedAt case final expectedMod?
        when TaskItem.normalizeTimestamp(expectedMod) !=
            surviving.effectiveModifiedAt) {
      return false;
    }
    if (bound.expectedDeletionAt case final expectedDel?
        when TaskItem.normalizeTimestamp(expectedDel) !=
            deletedRecord.deletedAt) {
      return false;
    }
    if (bound.expectedLivePayloadSignature case final expectedSig?
        when expectedSig !=
            TdfPayloadComparison.locationPayloadSignature(surviving)) {
      return false;
    }
    return true;
  }

  /// Verifies whether [bound] matches [surviving] (including `dueAnchor`) and [deletedRecord] (`TDF-DEL-003`).
  static bool _matchesBoundTaskDecision(
    TdfBoundDeletionDecision bound,
    TaskItem surviving,
    TdfDeletedTaskRecord deletedRecord,
  ) {
    if (bound.expectedLiveModifiedAt case final expectedMod?
        when TaskItem.normalizeTimestamp(expectedMod) !=
            surviving.effectiveModifiedAt) {
      return false;
    }
    if (bound.expectedDeletionAt case final expectedDel?
        when TaskItem.normalizeTimestamp(expectedDel) !=
            deletedRecord.deletedAt) {
      return false;
    }
    if (bound.expectedLivePayloadSignature case final expectedSig?
        when expectedSig !=
            TdfPayloadComparison.taskPayloadSignature(surviving)) {
      return false;
    }
    return true;
  }

  /// Returns the maximum of three integers.
  static int _max3Int(int first, int second, int third) {
    final maxFirstSecond = first >= second ? first : second;
    return maxFirstSecond >= third ? maxFirstSecond : third;
  }

  /// Classifies a single task [id] into [liveById], [twoSidedHeadersById], [deletedIds], or [pendingCandidates] for prerequisite previewing.
  static void _processSinglePreviewTask({
    required String id,
    required TaskItem? primaryTask,
    required TaskItem? secondaryTask,
    required TaskItem? baselineTask,
    required Map<String, TdfDeletedTaskRecord> initialDeleted,
    required _ReconcileContext context,
    required Map<String, TdfDeletionResolution> resolutions,
    required Map<String, TdfBoundDeletionDecision> boundDecisions,
    required Map<String, TdfRecoveryResolution> recoveryResolutions,
    required Set<String> freshlyRecoveredIds,
    required Map<String, TaskItem> liveById,
    required Map<String, TaskItem> twoSidedHeadersById,
    required Set<String> deletedIds,
    required List<_PreviewDeleteCandidate> pendingCandidates,
  }) {
    if (primaryTask != null && secondaryTask != null) {
      final header = TdfPayloadComparison.previewMergedTaskPrerequisiteHeader(
        local: primaryTask,
        incoming: secondaryTask,
        baseline: baselineTask,
      );
      twoSidedHeadersById[id] = header;
      liveById[id] = header;
      return;
    }
    final surviving = primaryTask ?? secondaryTask;
    if (surviving == null) {
      return;
    }
    if (freshlyRecoveredIds.contains(id)) {
      liveById[id] = surviving;
      return;
    }
    final isStale = primaryTask != null
        ? context.primaryRefresh
        : context.secondaryRefresh;
    var previewRecord = initialDeleted[id];
    if (previewRecord == null && baselineTask != null && !isStale) {
      final synthAt = TaskItem.nextModifiedTimestamp(
        context.now,
        baselineTask.effectiveModifiedAt,
      );
      previewRecord = TdfDeletedTaskRecord(
        taskId: id,
        deletedAt: synthAt,
        completionsCheckpoint: baselineTask.completions,
      );
    }
    if (previewRecord != null) {
      final decision = _resolveEffectiveTaskDecision(
        surviving,
        previewRecord,
        resolutions,
        boundDecisions,
      );
      if (decision == TdfDeletionResolution.undelete) {
        final maxComp = _max3Int(
          surviving.completions,
          baselineTask?.completions ?? 0,
          previewRecord.completionsCheckpoint,
        );
        liveById[id] = surviving.copyWith(completions: maxComp);
        return;
      }
      if (decision == TdfDeletionResolution.delete) {
        deletedIds.add(id);
        return;
      }
      liveById[id] = surviving;
      if (baselineTask != null) {
        pendingCandidates.add((
          id: id,
          surviving: surviving,
          baselineTask: baselineTask,
        ));
      }
      return;
    }
    if (baselineTask != null) {
      if (recoveryResolutions[id] == TdfRecoveryResolution.discard) {
        deletedIds.add(id);
        return;
      }
      liveById[id] = surviving;
      pendingCandidates.add((
        id: id,
        surviving: surviving,
        baselineTask: baselineTask,
      ));
      return;
    }
    if (!isStale) {
      liveById[id] = surviving;
    } else if (recoveryResolutions[id] == TdfRecoveryResolution.discard) {
      deletedIds.add(id);
    } else {
      liveById[id] = surviving;
    }
  }

  /// Promotes unchanged one-sided deletion candidates into [deletedIds] and removes them from [liveById] (`TDF-DEL-002`).
  static ({List<_PreviewDeleteCandidate> remaining, bool promotedAny})
  _promoteUnchangedPreviewCandidates(
    List<_PreviewDeleteCandidate> candidates, {
    required Map<String, TaskItem> liveById,
    required Set<String> deletedIds,
    required DateTime nowUtc,
  }) {
    final remaining = <_PreviewDeleteCandidate>[];
    var promotedAny = false;
    for (final candidate in candidates) {
      if (_isTaskUnchangedFromBaseline(
        candidate.surviving,
        candidate.baselineTask,
        previewLiveTasksById: liveById,
        previewDeletedTaskIds: deletedIds,
        nowUtc: nowUtc,
      )) {
        liveById.remove(candidate.id);
        deletedIds.add(candidate.id);
        promotedAny = true;
      } else {
        remaining.add(candidate);
      }
    }
    return (remaining: remaining, promotedAny: promotedAny);
  }

  /// Precomputes symmetric generation refresh flags and [now] for entity reconciliation.
  static _ReconcileContext _reconcileContext(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    (int?, bool, DateTime) options,
  ) {
    final (ackGen, requireAck, now) = options;
    final flags = resolveGenerationRefreshFlags(boards, ackGen, requireAck);
    return (
      primaryRefresh: flags.primaryRefresh,
      secondaryRefresh: flags.secondaryRefresh,
      now: now,
    );
  }

  /// Reconciles a one-sided task [id] and returns whether an explicit `Undelete` retired a deletion record.
  static bool _reconcileOneSidedTask(
    String id,
    (TaskItem?, TaskItem?, TaskItem?) entities,
    _ReconcileContext context,
    _TaskAccumulator accumulator, {
    required Map<String, TdfDeletionResolution> resolutions,
    required Map<String, TdfBoundDeletionDecision> boundDecisions,
    required Map<String, TdfRecoveryResolution> recoveryResolutions,
    required Set<String> freshlyRecoveredIds,
    required Map<String, TaskItem> previewLiveTasksById,
    required Set<String> previewDeletedTaskIds,
  }) {
    final (primaryTask, secondaryTask, baselineTask) = entities;
    final surviving = primaryTask ?? secondaryTask;
    if (surviving == null) {
      return false;
    }
    if (freshlyRecoveredIds.contains(id)) {
      accumulator.live.add(surviving);
      accumulator.uncleanedById[id] = surviving;
      return false;
    }
    final isStale = primaryTask != null
        ? context.primaryRefresh
        : context.secondaryRefresh;
    final unchanged =
        baselineTask != null &&
        _isTaskUnchangedFromBaseline(
          surviving,
          baselineTask,
          previewLiveTasksById: previewLiveTasksById,
          previewDeletedTaskIds: previewDeletedTaskIds,
          nowUtc: context.now,
        );

    final TdfDeletedTaskRecord conflictRecord;
    if (accumulator.deleted[id] case final existing?) {
      if (unchanged) {
        final maxComp = _max3Int(
          existing.completionsCheckpoint,
          surviving.completions,
          baselineTask.completions,
        );
        accumulator.deleted[id] = TdfDeletedTaskRecord(
          taskId: id,
          deletedAt: existing.deletedAt,
          completionsCheckpoint: maxComp,
        );
        return false;
      }
      conflictRecord = existing;
    } else if (baselineTask != null) {
      if (isStale) {
        if (unchanged ||
            recoveryResolutions[id] == TdfRecoveryResolution.discard) {
          accumulator.discardedIds.add(id);
        } else {
          accumulator.ambiguous.add(id);
        }
        return false;
      }
      final synthAt = TaskItem.nextModifiedTimestamp(
        context.now,
        baselineTask.effectiveModifiedAt,
      );
      conflictRecord = TdfDeletedTaskRecord(
        taskId: id,
        deletedAt: synthAt,
        completionsCheckpoint: baselineTask.completions,
      );
      if (unchanged) {
        accumulator.deleted[id] = conflictRecord;
        return false;
      }
    } else {
      if (isStale) {
        if (recoveryResolutions[id] == TdfRecoveryResolution.discard) {
          accumulator.discardedIds.add(id);
        } else {
          accumulator.ambiguous.add(id);
        }
      } else {
        accumulator.live.add(surviving);
        accumulator.uncleanedById[id] = surviving;
      }
      return false;
    }
    final conflict = (surviving, baselineTask, conflictRecord);
    return _resolveTaskDeletionConflict(
      conflict,
      context,
      accumulator,
      resolutions: resolutions,
      boundDecisions: boundDecisions,
    );
  }

  /// Reconciles a single label [id] and returns whether an explicit `Undelete` retired a deletion record.
  static bool _reconcileSingleLabel(
    String id,
    (TdfLabel?, TdfLabel?, TdfLabel?) entities,
    _ReconcileContext context,
    _LabelAccumulator accumulator, {
    required Map<String, TdfDeletionResolution> resolutions,
    required Map<String, TdfBoundDeletionDecision> boundDecisions,
    required Map<String, TdfRecoveryResolution> recoveryResolutions,
    required Set<String> freshlyRecoveredIds,
    required Set<String> tombstonedLocationIds,
    required Set<String> newlyReferencedLabelIds,
  }) {
    final (primaryLabel, secondaryLabel, baselineLabel) = entities;
    if (primaryLabel != null && secondaryLabel != null) {
      final mergedLabel = TdfPayloadComparison.mergeLabelWithBaseline(
        local: primaryLabel,
        incoming: secondaryLabel,
        baseline: baselineLabel,
        tombstonedLocationIds: tombstonedLocationIds,
      );
      final winner = identical(mergedLabel, primaryLabel)
          ? 'primary'
          : (identical(mergedLabel, secondaryLabel) ? 'secondary' : 'merged');
      AppLogger.event(
        LogLevel.debug,
        LogTag.sync,
        'sync.reconcile.label',
        fields: <String, Object?>{
          'id': id,
          'winner': winner,
          'primary_rev': primaryLabel.effectiveModifiedAt.toIso8601String(),
          'secondary_rev': secondaryLabel.effectiveModifiedAt.toIso8601String(),
        },
      );
      accumulator.live.add(mergedLabel);
      return false;
    }

    final surviving = primaryLabel ?? secondaryLabel;
    if (surviving == null) {
      return false;
    }
    if (freshlyRecoveredIds.contains(id)) {
      accumulator.live.add(surviving);
      return false;
    }
    final isStale = primaryLabel != null
        ? context.primaryRefresh
        : context.secondaryRefresh;
    final unchanged =
        baselineLabel != null &&
        _isLabelUnchangedFromBaseline(surviving, baselineLabel) &&
        !newlyReferencedLabelIds.contains(id);

    final TdfDeletedLabelRecord conflictRecord;
    if (accumulator.deleted[id] case final existingDeleted?) {
      if (unchanged) {
        return false;
      }
      conflictRecord = existingDeleted;
    } else if (baselineLabel != null) {
      if (isStale) {
        if (unchanged ||
            recoveryResolutions[id] == TdfRecoveryResolution.discard) {
          accumulator.discarded.add(id);
        } else {
          accumulator.ambiguous.add(id);
        }
        return false;
      }
      final synthAt = TaskItem.nextModifiedTimestamp(
        context.now,
        baselineLabel.effectiveModifiedAt,
      );
      conflictRecord = TdfDeletedLabelRecord(labelId: id, deletedAt: synthAt);
      if (unchanged) {
        accumulator.deleted[id] = conflictRecord;
        return false;
      }
    } else {
      if (isStale) {
        if (recoveryResolutions[id] == TdfRecoveryResolution.discard) {
          accumulator.discarded.add(id);
        } else {
          accumulator.ambiguous.add(id);
        }
      } else {
        accumulator.live.add(surviving);
      }
      return false;
    }
    final conflict = (surviving, baselineLabel, conflictRecord);
    return _resolveLabelDeletionConflict(
      conflict,
      context,
      accumulator,
      resolutions: resolutions,
      boundDecisions: boundDecisions,
    );
  }

  /// Reconciles a single location [id] and returns whether an explicit `Undelete` retired a deletion record.
  static bool _reconcileSingleLocation(
    String id,
    (TdfLocation?, TdfLocation?, TdfLocation?) entities,
    _ReconcileContext context,
    _LocationAccumulator accumulator, {
    required Map<String, TdfDeletionResolution> resolutions,
    required Map<String, TdfBoundDeletionDecision> boundDecisions,
    required Map<String, TdfRecoveryResolution> recoveryResolutions,
    required Set<String> freshlyRecoveredIds,
    required Set<String> newlyReferencedLocationIds,
  }) {
    final (primaryLoc, secondaryLoc, baselineLoc) = entities;
    if (primaryLoc != null && secondaryLoc != null) {
      final mergedLoc = TdfPayloadComparison.mergeLocationWithBaseline(
        local: primaryLoc,
        incoming: secondaryLoc,
        baseline: baselineLoc,
      );
      final winner = identical(mergedLoc, primaryLoc)
          ? 'primary'
          : (identical(mergedLoc, secondaryLoc) ? 'secondary' : 'merged');
      AppLogger.event(
        LogLevel.debug,
        LogTag.sync,
        'sync.reconcile.location',
        fields: <String, Object?>{
          'id': id,
          'winner': winner,
          'primary_rev': primaryLoc.effectiveModifiedAt.toIso8601String(),
          'secondary_rev': secondaryLoc.effectiveModifiedAt.toIso8601String(),
        },
      );
      accumulator.live.add(mergedLoc);
      return false;
    }

    final surviving = primaryLoc ?? secondaryLoc;
    if (surviving == null) {
      return false;
    }
    if (freshlyRecoveredIds.contains(id)) {
      accumulator.live.add(surviving);
      return false;
    }
    final isStale = primaryLoc != null
        ? context.primaryRefresh
        : context.secondaryRefresh;
    final unchanged =
        baselineLoc != null &&
        _isLocationUnchangedFromBaseline(surviving, baselineLoc) &&
        !newlyReferencedLocationIds.contains(id);

    final TdfDeletedLocationRecord conflictRecord;
    if (accumulator.deleted[id] case final existingDeleted?) {
      if (unchanged) {
        return false;
      }
      conflictRecord = existingDeleted;
    } else if (baselineLoc != null) {
      if (isStale) {
        if (unchanged ||
            recoveryResolutions[id] == TdfRecoveryResolution.discard) {
          accumulator.discarded.add(id);
        } else {
          accumulator.ambiguous.add(id);
        }
        return false;
      }
      final synthAt = TaskItem.nextModifiedTimestamp(
        context.now,
        baselineLoc.effectiveModifiedAt,
      );
      conflictRecord = TdfDeletedLocationRecord(
        locationId: id,
        deletedAt: synthAt,
      );
      if (unchanged) {
        accumulator.deleted[id] = conflictRecord;
        return false;
      }
    } else {
      if (isStale) {
        if (recoveryResolutions[id] == TdfRecoveryResolution.discard) {
          accumulator.discarded.add(id);
        } else {
          accumulator.ambiguous.add(id);
        }
      } else {
        accumulator.live.add(surviving);
      }
      return false;
    }
    final conflict = (surviving, baselineLoc, conflictRecord);
    return _resolveLocationDeletionConflict(
      conflict,
      context,
      accumulator,
      resolutions: resolutions,
      boundDecisions: boundDecisions,
    );
  }

  /// Reconciles a two-sided task [id] present on both boards and records its `uncleaned` counterpart into [uncleanedOut].
  static ({TaskItem task, bool wasUnchanged}) _reconcileTwoSidedTask({
    required String id,
    required TaskItem local,
    required TaskItem incoming,
    required TaskItem? baseline,
    required DateTime now,
    required TdfCleanupMode cleanupMode,
    required Map<String, TaskItem> mergedLiveTasksById,
    required Set<String> mergedDeletedTaskIds,
    required Set<String> tombstonedLocationIds,
    required Set<String> deletedLabelsLocal,
    required Set<String> deletedLabelsIncoming,
    required Set<String>? validLabelIds,
    required Map<String, TdfLabel> postCascadeLabelsById,
    required Map<String, TaskItem> uncleanedOut,
    List<({String event, Map<String, Object?> fields})>? debugEntriesOut,
  }) {
    final mergedResult = TdfPayloadComparison.mergeTaskWithBaselineAndUncleaned(
      local: local,
      incoming: incoming,
      baseline: baseline,
      evaluationTime: now,
      cleanupMode: cleanupMode,
      mergedLiveTasksById: mergedLiveTasksById,
      mergedDeletedTaskIds: mergedDeletedTaskIds,
      tombstonedLocationIds: tombstonedLocationIds,
      deletedLabelsLocal: deletedLabelsLocal,
      deletedLabelsIncoming: deletedLabelsIncoming,
      validLabelIds: validLabelIds,
      postCascadeLabelsById: postCascadeLabelsById,
    );
    uncleanedOut[id] = mergedResult.uncleaned;
    final mergedTask = mergedResult.merged;
    final isIdenticalUnchanged =
        mergedResult.wasUnchangedIdentity ||
        (local == incoming && mergedTask == local);
    if (debugEntriesOut != null && !isIdenticalUnchanged) {
      final winner =
          TdfPayloadComparison.taskPayloadsEqual(mergedTask, local) &&
              mergedTask.modifiedAt == local.modifiedAt
          ? 'primary'
          : (TdfPayloadComparison.taskPayloadsEqual(mergedTask, incoming) &&
                    mergedTask.modifiedAt == incoming.modifiedAt
                ? 'secondary'
                : 'merged');
      debugEntriesOut.add((
        event: 'sync.reconcile.task',
        fields: <String, Object?>{
          'id': id,
          'winner': winner,
          'primary_rev': local.effectiveModifiedAt.toIso8601String(),
          'secondary_rev': incoming.effectiveModifiedAt.toIso8601String(),
        },
      ));
    }
    return (task: mergedTask, wasUnchanged: isIdenticalUnchanged);
  }

  /// Resolves the verified [TdfDeletionResolution] for [surviving] and [deletedRecord] from [boundDecisions] or [resolutions].
  static TdfDeletionResolution? _resolveEffectiveLabelDecision(
    TdfLabel surviving,
    TdfDeletedLabelRecord deletedRecord,
    Map<String, TdfDeletionResolution> resolutions,
    Map<String, TdfBoundDeletionDecision> boundDecisions,
  ) {
    final id = surviving.id;
    if (boundDecisions[id] case final bound?) {
      if (!_matchesBoundLabelDecision(bound, surviving, deletedRecord)) {
        return null;
      }
      return bound.resolution;
    }
    return resolutions[id];
  }

  /// Resolves the verified [TdfDeletionResolution] for [surviving] and [deletedRecord] from [boundDecisions] or [resolutions].
  static TdfDeletionResolution? _resolveEffectiveLocationDecision(
    TdfLocation surviving,
    TdfDeletedLocationRecord deletedRecord,
    Map<String, TdfDeletionResolution> resolutions,
    Map<String, TdfBoundDeletionDecision> boundDecisions,
  ) {
    final id = surviving.id;
    if (boundDecisions[id] case final bound?) {
      if (!_matchesBoundLocationDecision(bound, surviving, deletedRecord)) {
        return null;
      }
      return bound.resolution;
    }
    return resolutions[id];
  }

  /// Resolves the verified [TdfDeletionResolution] for [surviving] and [deletedRecord] from [boundDecisions] or [resolutions].
  static TdfDeletionResolution? _resolveEffectiveTaskDecision(
    TaskItem surviving,
    TdfDeletedTaskRecord deletedRecord,
    Map<String, TdfDeletionResolution> resolutions,
    Map<String, TdfBoundDeletionDecision> boundDecisions,
  ) {
    final id = surviving.id;
    if (boundDecisions[id] case final bound?) {
      if (!_matchesBoundTaskDecision(bound, surviving, deletedRecord)) {
        return null;
      }
      return bound.resolution;
    }
    return resolutions[id];
  }

  /// Applies the verified conflict resolution (or records a `DeletionConflict`) for [conflict] (`TDF-DEL-003`).
  static bool _resolveLabelDeletionConflict(
    (TdfLabel, TdfLabel?, TdfDeletedLabelRecord) conflict,
    _ReconcileContext context,
    _LabelAccumulator accumulator, {
    required Map<String, TdfDeletionResolution> resolutions,
    required Map<String, TdfBoundDeletionDecision> boundDecisions,
  }) {
    final (surviving, baselineLabel, deletedRecord) = conflict;
    final id = surviving.id;
    final resolution = _resolveEffectiveLabelDecision(
      surviving,
      deletedRecord,
      resolutions,
      boundDecisions,
    );
    if (resolution == null) {
      accumulator.conflicted.add(id);
      return false;
    }
    final revisions = (
      surviving.effectiveModifiedAt,
      deletedRecord.deletedAt,
      baselineLabel?.effectiveModifiedAt,
    );
    final revision = _computeDecisionRevision(revisions, context.now);
    switch (resolution) {
      case TdfDeletionResolution.delete:
        accumulator.deleted[id] = TdfDeletedLabelRecord(
          labelId: id,
          deletedAt: revision,
        );
        accumulator.explicitlyDeleted.add(id);
        return false;
      case TdfDeletionResolution.undelete:
        accumulator.deleted.remove(id);
        accumulator.live.add(surviving.copyWith(modifiedAt: revision));
        return true;
    }
  }

  /// Applies the verified conflict resolution (or records a `DeletionConflict`) for [conflict] (`TDF-DEL-003`).
  static bool _resolveLocationDeletionConflict(
    (TdfLocation, TdfLocation?, TdfDeletedLocationRecord) conflict,
    _ReconcileContext context,
    _LocationAccumulator accumulator, {
    required Map<String, TdfDeletionResolution> resolutions,
    required Map<String, TdfBoundDeletionDecision> boundDecisions,
  }) {
    final (surviving, baselineLoc, deletedRecord) = conflict;
    final id = surviving.id;
    final resolution = _resolveEffectiveLocationDecision(
      surviving,
      deletedRecord,
      resolutions,
      boundDecisions,
    );
    if (resolution == null) {
      accumulator.conflicted.add(id);
      return false;
    }
    final revisions = (
      surviving.effectiveModifiedAt,
      deletedRecord.deletedAt,
      baselineLoc?.effectiveModifiedAt,
    );
    final revision = _computeDecisionRevision(revisions, context.now);
    switch (resolution) {
      case TdfDeletionResolution.delete:
        accumulator.deleted[id] = TdfDeletedLocationRecord(
          locationId: id,
          deletedAt: revision,
        );
        accumulator.explicitlyDeleted.add(id);
        return false;
      case TdfDeletionResolution.undelete:
        accumulator.deleted.remove(id);
        accumulator.live.add(surviving.copyWith(modifiedAt: revision));
        return true;
    }
  }

  /// Applies the verified conflict resolution (or records a `DeletionConflict`) for [conflict] (`TDF-DEL-003`).
  static bool _resolveTaskDeletionConflict(
    (TaskItem, TaskItem?, TdfDeletedTaskRecord) conflict,
    _ReconcileContext context,
    _TaskAccumulator accumulator, {
    required Map<String, TdfDeletionResolution> resolutions,
    required Map<String, TdfBoundDeletionDecision> boundDecisions,
  }) {
    final (surviving, baselineTask, deletedRecord) = conflict;
    final id = surviving.id;
    final resolution = _resolveEffectiveTaskDecision(
      surviving,
      deletedRecord,
      resolutions,
      boundDecisions,
    );
    if (resolution == null) {
      accumulator.conflicted.add(id);
      return false;
    }
    final revisions = (
      surviving.effectiveModifiedAt,
      deletedRecord.deletedAt,
      baselineTask?.effectiveModifiedAt,
    );
    final revision = _computeDecisionRevision(revisions, context.now);
    final maxComp = _max3Int(
      surviving.completions,
      baselineTask?.completions ?? 0,
      deletedRecord.completionsCheckpoint,
    );
    switch (resolution) {
      case TdfDeletionResolution.delete:
        accumulator.deleted[id] = TdfDeletedTaskRecord(
          taskId: id,
          deletedAt: revision,
          completionsCheckpoint: maxComp,
        );
        accumulator.explicitlyDeletedIds.add(id);
        return false;
      case TdfDeletionResolution.undelete:
        accumulator.deleted.remove(id);
        final restored = surviving.copyWith(
          completions: maxComp,
          modifiedAt: revision,
        );
        accumulator.live.add(restored);
        accumulator.uncleanedById[id] = restored;
        accumulator.undeletedIds.add(id);
        return true;
    }
  }

  /// Strips deleted or discarded labels from a single [task], applies `TDF-MERGE-011` `scoped` flood protection, and validates remaining label references.
  static TaskItem _stripDeletedLabelsFromSingleTask(
    TaskItem task,
    Set<String> validLabelIds,
    Map<String, TdfDeletedLabelRecord> deletedLabelsById,
    Set<String> baselineLabelSet, {
    required Set<String> discardedLabelIds,
    required Set<String> explicitlyDeletedLabelIds,
    required Set<String> scopedLabelSet,
    required Set<String> alreadyQueuedUnlabelledTaskIds,
    required Set<String>? evictedFromQueueOut,
    required (TaskItem?, TaskItem?, TaskItem?) sourceVariants,
    required Set<String>? mutatedByNowCascadeOut,
    required DateTime? now,
  }) {
    if (task.labelIds.isEmpty) {
      return task;
    }
    final retained = <String>[];
    var strippedAny = false;
    var strippedByMutation = false;
    var allBeforeWereScoped = true;

    for (final labelId in task.labelIds) {
      if (!scopedLabelSet.contains(labelId)) {
        allBeforeWereScoped = false;
      }
      if (validLabelIds.contains(labelId)) {
        retained.add(labelId);
        continue;
      }
      final isKnownDeleted =
          deletedLabelsById.containsKey(labelId) ||
          baselineLabelSet.contains(labelId) ||
          discardedLabelIds.contains(labelId);
      if (!isKnownDeleted) {
        throw TdfException(
          kind: TdfErrorKind.unknownLabelReference,
          line: 1,
          message:
              'Merged task "${task.id}" references undeclared label "$labelId".',
        );
      }
      strippedAny = true;
      strippedByMutation =
          strippedByMutation ||
          explicitlyDeletedLabelIds.contains(labelId) ||
          discardedLabelIds.contains(labelId);
    }

    if (!strippedAny) {
      return task;
    }
    if (strippedByMutation) {
      mutatedByNowCascadeOut?.add(task.id);
    }
    final isOpen = !task.isCompleted && task.completedAt == null;
    final lostLastScopedLabel =
        isOpen &&
        retained.isEmpty &&
        allBeforeWereScoped &&
        !alreadyQueuedUnlabelledTaskIds.contains(task.id);
    if (lostLastScopedLabel && evictedFromQueueOut != null) {
      evictedFromQueueOut.add(task.id);
    }
    return _finalizePostLabelCascadeTask(
      task,
      retained: retained,
      nextPriority: lostLastScopedLabel ? false : task.isPriority,
      strippedByMutation: strippedByMutation,
      sourceVariants: sourceVariants,
      now: now,
    );
  }

  /// Strips deleted or discarded locations from a single [label] and validates remaining location references.
  static TdfLabel _stripDeletedLocationsFromSingleLabel(
    TdfLabel label,
    Set<String> validLocationIds,
    Map<String, TdfDeletedLocationRecord> deletedLocationsById,
    Set<String> baselineLocationSet, {
    required Set<String> discardedLocationIds,
    required Set<String> explicitlyDeletedLocationIds,
    required (TdfLabel?, TdfLabel?, TdfLabel?) sourceVariants,
    required DateTime? now,
  }) {
    if (label.conditions.isEmpty) {
      return label;
    }
    final updatedConditions = <TaskCondition>[];
    var strippedAny = false;
    var strippedByMutation = false;

    for (final rule in label.conditions) {
      if (rule is! LocationTaskCondition || rule.locationIds.isEmpty) {
        updatedConditions.add(rule);
        continue;
      }
      final filtered = _filterLocationIdsForEntity(
        entityKind: 'label',
        entityId: label.id,
        locationIds: rule.locationIds,
        validLocationIds: validLocationIds,
        deletedLocationsById: deletedLocationsById,
        baselineLocationSet: baselineLocationSet,
        discardedLocationIds: discardedLocationIds,
        explicitlyDeletedLocationIds: explicitlyDeletedLocationIds,
      );
      if (filtered.strippedAny) {
        strippedAny = true;
        if (filtered.strippedByMutation) {
          strippedByMutation = true;
        }
      }
      if (filtered.retainedIds.isNotEmpty) {
        updatedConditions.add(
          LocationTaskCondition(locationIds: filtered.retainedIds),
        );
      }
    }

    if (!strippedAny) {
      return label;
    }
    return _finalizePostLocationCascadeLabel(
      label,
      updatedConditions: updatedConditions,
      strippedByMutation: strippedByMutation,
      sourceVariants: sourceVariants,
      now: now,
    );
  }

  /// Strips deleted or discarded locations from a single [task] and validates remaining location references.
  static TaskItem _stripDeletedLocationsFromSingleTask(
    TaskItem task,
    Set<String> validLocationIds,
    Map<String, TdfDeletedLocationRecord> deletedLocationsById,
    Set<String> baselineLocationSet,
    Map<String, TdfLabel> postCascadeLabelsById, {
    required Set<String> discardedLocationIds,
    required Set<String> explicitlyDeletedLocationIds,
    required Set<String>? mutatedByNowCascadeOut,
    required DateTime? now,
  }) {
    if (task.conditions.isEmpty) {
      return task;
    }
    final updatedConditions = <TaskCondition>[];
    var strippedAny = false;
    var strippedByMutation = false;

    final hasAssignedLabelLocation = _hasLiveLabelLocationRule(
      task.labelIds,
      postCascadeLabelsById,
    );
    for (final rule in task.conditions) {
      if (rule is! LocationTaskCondition || rule.locationIds.isEmpty) {
        updatedConditions.add(rule);
        continue;
      }
      final filtered = _filterLocationIdsForEntity(
        entityKind: 'task',
        entityId: task.id,
        locationIds: rule.locationIds,
        validLocationIds: validLocationIds,
        deletedLocationsById: deletedLocationsById,
        baselineLocationSet: baselineLocationSet,
        discardedLocationIds: discardedLocationIds,
        explicitlyDeletedLocationIds: explicitlyDeletedLocationIds,
      );
      strippedAny = strippedAny || filtered.strippedAny;
      strippedByMutation = strippedByMutation || filtered.strippedByMutation;
      if (filtered.retainedIds.isNotEmpty) {
        updatedConditions.add(
          LocationTaskCondition(locationIds: filtered.retainedIds),
        );
      } else if (hasAssignedLabelLocation) {
        updatedConditions.add(
          const GroupResetTaskCondition(targetGroup: ConditionGroup.location),
        );
      }
    }

    if (!strippedAny) {
      return task;
    }
    if (strippedByMutation) {
      mutatedByNowCascadeOut?.add(task.id);
    }
    if (strippedByMutation && now != null) {
      return task.copyWith(
        conditions: updatedConditions,
        modifiedAt: TaskItem.nextModifiedTimestamp(
          now,
          task.effectiveModifiedAt,
        ),
      );
    }
    return task.copyWith(
      conditions: updatedConditions,
      modifiedAt: _validatedPlusOneSecond(task.effectiveModifiedAt),
    );
  }

  /// Adds one second to [timestamp] and validates TDF calendar bounds.
  static DateTime _validatedPlusOneSecond(DateTime timestamp) {
    final bumped = timestamp.add(const Duration(seconds: 1));
    if (!TdfCalendar.isWithinTimestampBounds(bumped)) {
      throw const TdfException(
        kind: TdfErrorKind.invalidTimestamp,
        line: 1,
        message: 'Merged revision exceeds maximum supported timestamp.',
      );
    }
    return bumped;
  }
}

/// Result of reconciling `task` blocks and task deletion records.
@immutable
class TaskReconciliationOutcome {
  /// Creates a [TaskReconciliationOutcome].
  const TaskReconciliationOutcome({
    required this.liveTasks,
    required this.deletedTasksById,
    required this.conflictedIds,
    required this.ambiguousIds,
    required this.retiredByUndelete,
    this.uncleanedLiveTasksById = const <String, TaskItem>{},
    this.undeletedTaskIds = const <String>{},
    this.discardedTaskIds = const <String>{},
    this.explicitlyDeletedTaskIds = const <String>{},
  });

  /// Task IDs requiring user recovery after deletion history expiry or completion regression.
  final List<String> ambiguousIds;

  /// Task IDs with unresolved deletion vs. modification conflicts.
  final List<String> conflictedIds;

  /// Active task deletion records keyed by task ID.
  final Map<String, TdfDeletedTaskRecord> deletedTasksById;

  /// Stale-side task IDs discarded during generation refresh or explicit `discard` recovery (`TDF-REC-002`).
  final Set<String> discardedTaskIds;

  /// Task IDs resolved via explicit `Delete` during `DeletionConflict` resolution (`TDF-DEL-003`).
  final Set<String> explicitlyDeletedTaskIds;

  /// Surviving reconciled live tasks.
  final List<TaskItem> liveTasks;

  /// Whether at least one deletion record was retired by an explicit undelete resolution.
  final bool retiredByUndelete;

  /// Pre-cleanup merged task payloads keyed by task ID for `TDF-MERGE-004` revision selection.
  final Map<String, TaskItem> uncleanedLiveTasksById;

  /// Task IDs resolved via explicit `Undelete` during this reconciliation pass.
  final Set<String> undeletedTaskIds;
}

/// Mutable accumulator used while reconciling labels across two boards.
typedef _LabelAccumulator = ({
  List<TdfLabel> live,
  Map<String, TdfDeletedLabelRecord> deleted,
  List<String> conflicted,
  List<String> ambiguous,
  Set<String> discarded,
  Set<String> explicitlyDeleted,
});

/// Mutable accumulator used while reconciling locations across two boards.
typedef _LocationAccumulator = ({
  List<TdfLocation> live,
  Map<String, TdfDeletedLocationRecord> deleted,
  List<String> conflicted,
  List<String> ambiguous,
  Set<String> discarded,
  Set<String> explicitlyDeleted,
});

/// One-sided deletion candidate pending baseline-cleanup unchanged verification during prerequisite preview.
typedef _PreviewDeleteCandidate = ({
  String id,
  TaskItem surviving,
  TaskItem baselineTask,
});

/// Precomputed symmetric generation refresh flags and evaluation instant.
typedef _ReconcileContext = ({
  bool primaryRefresh,
  bool secondaryRefresh,
  DateTime now,
});

/// Mutable accumulator used while reconciling tasks across two boards.
typedef _TaskAccumulator = ({
  List<TaskItem> live,
  Map<String, TaskItem> uncleanedById,
  Set<String> undeletedIds,
  Set<String> discardedIds,
  Set<String> explicitlyDeletedIds,
  Map<String, TdfDeletedTaskRecord> deleted,
  List<String> conflicted,
  List<String> ambiguous,
});
