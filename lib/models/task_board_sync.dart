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
import 'task_board_evaluator.dart';
import 'task_board_reconciler.dart';
import 'task_item.dart';
import 'tdf_error.dart';
import 'tdf_location.dart';
import 'tdf_metadata.dart';
import 'tdf_payload_comparison.dart';
import 'tdf_sync_metadata.dart';
import 'tdf_timezone.dart';

/// Stateless entity-level synchronization, three-way merge, deletion record
/// reconciliation, recovery rewriting, and shared queue merge engine for
/// [TaskBoard] documents per `spec/TDF_SPEC_0.8.0.md` Sections 11–13.
@immutable
class TaskBoardSync {
  /// Prevents instantiation of this stateless helper class.
  const TaskBoardSync._();

  /// Combines active deletion records from [primary] and [secondary], discarding superseded acknowledged records on a stale generation side (`TDF-DEL-001`, `TDF-REC-001`).
  static ({
    Map<String, TdfDeletedTaskRecord> tasks,
    Map<String, TdfDeletedLabelRecord> labels,
    Map<String, TdfDeletedLocationRecord> locations,
  })
  combineInitialDeletedRecords(
    TdfDeletedBlock primary,
    TdfDeletedBlock secondary,
    TdfDeletedBlock? baseline, [
    bool discardPrimaryAcked = false,
    bool discardSecondaryAcked = false,
  ]) {
    final discardPrimary =
        discardPrimaryAcked || primary.generation < secondary.generation;
    final discardSecondary =
        discardSecondaryAcked || secondary.generation < primary.generation;

    final taskRecords = <String, TdfDeletedTaskRecord>{
      for (final record in primary.tasks)
        if (!_isAckedTask(record, baseline, discardPrimary))
          record.taskId: record,
    };
    for (final record in secondary.tasks) {
      if (!_isAckedTask(record, baseline, discardSecondary)) {
        final previous = taskRecords[record.taskId];
        taskRecords[record.taskId] = previous?.mergeWith(record) ?? record;
      }
    }

    final labelRecords = <String, TdfDeletedLabelRecord>{
      for (final record in primary.labels)
        if (!_isAckedLabel(record, baseline, discardPrimary))
          record.labelId: record,
    };
    for (final record in secondary.labels) {
      if (!_isAckedLabel(record, baseline, discardSecondary)) {
        final previous = labelRecords[record.labelId];
        if (previous == null || record.deletedAt.isAfter(previous.deletedAt)) {
          labelRecords[record.labelId] = record;
        }
      }
    }

    final locationRecords = <String, TdfDeletedLocationRecord>{
      for (final record in primary.locations)
        if (!_isAckedLocation(record, baseline, discardPrimary))
          record.locationId: record,
    };
    for (final record in secondary.locations) {
      if (!_isAckedLocation(record, baseline, discardSecondary)) {
        final previous = locationRecords[record.locationId];
        if (previous == null || record.deletedAt.isAfter(previous.deletedAt)) {
          locationRecords[record.locationId] = record;
        }
      }
    }

    return (
      tasks: taskRecords,
      labels: labelRecords,
      locations: locationRecords,
    );
  }

  /// Prunes expired deletion records (> `2,592,000` seconds) and increments `generation` at most once per transaction when records are retired (`TDF-PUB-004`).
  static TdfDeletedBlock finalizeDeletedBlock(
    int baseGeneration,
    Map<String, TdfDeletedTaskRecord> deletedTasks,
    Map<String, TdfDeletedLabelRecord> deletedLabels,
    bool retiredByUndelete,
    bool pruneExpired,
    DateTime now, [
    Map<String, TdfDeletedLocationRecord> deletedLocations = const {},
    int? unincrementedBaseGeneration,
  ]) {
    final activeTasks = <TdfDeletedTaskRecord>[
      for (final record in deletedTasks.values)
        if (!_isDeletedRecordExpired(record.deletedAt, now, pruneExpired))
          record,
    ];
    final activeLabels = <TdfDeletedLabelRecord>[
      for (final record in deletedLabels.values)
        if (!_isDeletedRecordExpired(record.deletedAt, now, pruneExpired))
          record,
    ];
    final activeLocations = <TdfDeletedLocationRecord>[
      for (final record in deletedLocations.values)
        if (!_isDeletedRecordExpired(record.deletedAt, now, pruneExpired))
          record,
    ];
    if (activeTasks.length + activeLabels.length + activeLocations.length >
        TdfDeletedBlock.maxDeletedRecords) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged deleted block exceeds MAX_DELETED_RECORDS ($maxTdfDeletedRecords).',
      );
    }

    final anyExpired =
        activeTasks.length != deletedTasks.length ||
        activeLabels.length != deletedLabels.length ||
        activeLocations.length != deletedLocations.length;
    var nextGeneration = baseGeneration;
    if (anyExpired || retiredByUndelete) {
      final incrementFloor = unincrementedBaseGeneration ?? baseGeneration;
      if (incrementFloor >= TdfDeletedBlock.maxGeneration) {
        _throwTdf(
          TdfErrorKind.limitExceeded,
          'Deletion history generation exceeds MAX_SYNC_GENERATION ($maxTdfSyncGeneration).',
        );
      }
      final incremented = incrementFloor + 1;
      nextGeneration = incremented > baseGeneration
          ? incremented
          : baseGeneration;
    }
    return TdfDeletedBlock(
      generation: nextGeneration,
      tasks: activeTasks,
      labels: activeLabels,
      locations: activeLocations,
    );
  }

  /// Executes the 9-phase `TDF-SYNC-002` reconciliation pipeline across [primary] (`L`) and [secondary] (`R`).
  static TaskBoard merge({
    required TaskBoard primary,
    required TaskBoard secondary,
    TaskBoard? baseline,
    int? acknowledgedGeneration,
    int? preTransactionPrimaryGeneration,
    Map<String, TdfDeletionResolution> taskConflictResolutions = const {},
    Map<String, TdfDeletionResolution> labelConflictResolutions = const {},
    Map<String, TdfDeletionResolution> locationConflictResolutions = const {},
    Map<String, TdfBoundDeletionDecision> boundTaskConflictDecisions = const {},
    Map<String, TdfBoundDeletionDecision> boundLabelConflictDecisions =
        const {},
    Map<String, TdfBoundDeletionDecision> boundLocationConflictDecisions =
        const {},
    Map<String, TdfRecoveryResolution> taskRecoveryResolutions = const {},
    Map<String, TdfRecoveryResolution> labelRecoveryResolutions = const {},
    Map<String, TdfRecoveryResolution> locationRecoveryResolutions = const {},
    Set<String> extraFreshlyRecoveredTaskIds = const <String>{},
    Set<String> extraRewrittenLabelIds = const <String>{},
    Set<String> extraRewrittenTaskIds = const <String>{},
    Set<String> extraDiscardedTaskIds = const <String>{},
    required DateTime evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
    bool pruneExpiredDeleted = true,
    bool pruneExpiredCompleted = true,
    bool requireAcknowledgedGeneration = false,
    TdfCleanupMode cleanupMode = TdfCleanupMode.finalStage,
  }) {
    final now = TaskItem.normalizeTimestamp(evaluationTime);
    final ackGen = acknowledgedGeneration ?? baseline?.deletedBlock.generation;
    final rawBoards = (primary, secondary, baseline);

    TaskBoardReconciler.verifyGenerationsAndCompletionHistory(
      rawBoards,
      ackGen,
    );
    final refreshFlags = TaskBoardReconciler.resolveGenerationRefreshFlags(
      rawBoards,
      ackGen,
      requireAcknowledgedGeneration,
    );
    final inlineRewrite = _applyInlineRecoveryRewrite(
      primary: primary,
      secondary: secondary,
      baseline: baseline,
      primaryRefresh: refreshFlags.primaryRefresh,
      secondaryRefresh: refreshFlags.secondaryRefresh,
      taskRecoveryResolutions: taskRecoveryResolutions,
      labelRecoveryResolutions: labelRecoveryResolutions,
      locationRecoveryResolutions: locationRecoveryResolutions,
      now: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
    );
    final effectivePrimary = inlineRewrite.primary;
    final effectiveSecondary = inlineRewrite.secondary;
    final boards = (effectivePrimary, effectiveSecondary, baseline);
    final options = (ackGen, requireAcknowledgedGeneration, now);
    final allFreshlyRecoveredTaskIds = <String>{
      ...inlineRewrite.freshlyRecoveredTaskIds,
      ...extraFreshlyRecoveredTaskIds,
    };

    final initialDeleted = combineInitialDeletedRecords(
      effectivePrimary.deletedBlock,
      effectiveSecondary.deletedBlock,
      baseline?.deletedBlock,
      refreshFlags.primaryRefresh,
      refreshFlags.secondaryRefresh,
    );
    final explicitlyDeletedTaskIds =
        TaskBoardReconciler.computeExplicitlyDeletedTaskIds(
          boards,
          initialDeleted.tasks,
          options,
          resolutions: taskConflictResolutions,
          boundDecisions: boundTaskConflictDecisions,
          recoveryResolutions: taskRecoveryResolutions,
          freshlyRecoveredIds: allFreshlyRecoveredTaskIds,
        );
    final explicitlyDeletedLabelIds =
        TaskBoardReconciler.computeExplicitlyDeletedLabelIds(
          boards,
          initialDeleted.labels,
          options,
          resolutions: labelConflictResolutions,
          boundDecisions: boundLabelConflictDecisions,
          recoveryResolutions: labelRecoveryResolutions,
          freshlyRecoveredIds: inlineRewrite.freshlyRecoveredLabelIds,
        );
    final newlyRefLocations =
        TaskBoardReconciler.computeNewlyReferencedLocationIds(
          boards,
          initialDeleted.tasks,
          initialDeleted.labels,
          explicitlyDeletedTaskIds: explicitlyDeletedTaskIds,
          explicitlyDeletedLabelIds: explicitlyDeletedLabelIds,
        );
    final locationOutcome = TaskBoardReconciler.reconcileLocations(
      boards,
      initialDeleted.locations,
      locationConflictResolutions,
      options,
      boundDecisions: boundLocationConflictDecisions,
      recoveryResolutions: locationRecoveryResolutions,
      freshlyRecoveredIds: inlineRewrite.freshlyRecoveredLocationIds,
      newlyReferencedLocationIds: newlyRefLocations,
    );
    final validLocationIds = <String>{
      for (final location in locationOutcome.liveLocations) location.id,
    };
    final tombstonedLocationIds = <String>{
      ...locationOutcome.deletedLocationsById.keys,
      ...locationOutcome.discardedIds,
      if (baseline != null)
        for (final location in baseline.locations)
          if (!validLocationIds.contains(location.id)) location.id,
    };

    final newlyRefLabels = TaskBoardReconciler.computeNewlyReferencedLabelIds(
      boards,
      initialDeleted.tasks,
      explicitlyDeletedTaskIds: explicitlyDeletedTaskIds,
    );
    final labelOutcome = TaskBoardReconciler.reconcileLabels(
      boards,
      initialDeleted.labels,
      labelConflictResolutions,
      options,
      boundDecisions: boundLabelConflictDecisions,
      recoveryResolutions: labelRecoveryResolutions,
      freshlyRecoveredIds: inlineRewrite.freshlyRecoveredLabelIds,
      tombstonedLocationIds: tombstonedLocationIds,
      newlyReferencedLabelIds: newlyRefLabels,
    );
    final validLabelIds = <String>{
      for (final label in labelOutcome.liveLabels) label.id,
    };
    final deletedLabelsPrimary = _computeDeletedLabelsForSide(
      side: effectivePrimary,
      baseline: baseline,
      isSideRefresh: refreshFlags.primaryRefresh,
    );
    final deletedLabelsSecondary = _computeDeletedLabelsForSide(
      side: effectiveSecondary,
      baseline: baseline,
      isSideRefresh: refreshFlags.secondaryRefresh,
    );
    final previewLabelsById = _previewPostCascadeLabels(
      labelOutcome.liveLabels,
      tombstonedLocationIds,
    );

    final taskOutcome = TaskBoardReconciler.reconcileTasks(
      boards,
      initialDeleted.tasks,
      taskConflictResolutions,
      options,
      boundDecisions: boundTaskConflictDecisions,
      recoveryResolutions: taskRecoveryResolutions,
      freshlyRecoveredIds: allFreshlyRecoveredTaskIds,
      tombstonedLocationIds: tombstonedLocationIds,
      deletedLabelsLocal: deletedLabelsPrimary,
      deletedLabelsIncoming: deletedLabelsSecondary,
      validLabelIds: validLabelIds,
      postCascadeLabelsById: previewLabelsById,
      cleanupMode: cleanupMode,
    );
    TaskBoardReconciler.checkSyncOutcomes(
      labelOutcome,
      taskOutcome,
      locationOutcome,
    );

    final labelsAfterStrip =
        TaskBoardReconciler.stripDeletedLocationsFromLabelsAndValidate(
          labelOutcome.liveLabels,
          validLocationIds,
          locationOutcome.deletedLocationsById,
          baseline?.locations,
          discardedLocationIds: locationOutcome.discardedIds,
          explicitlyDeletedLocationIds: locationOutcome.explicitlyDeletedIds,
          boards: boards,
          now: now,
        );
    final finalLabels = _advanceRewrittenLabels(labelsAfterStrip, <String>{
      ...extraRewrittenLabelIds,
      ...inlineRewrite.rewrittenLabelIds,
    }, now);
    final postCascadeLabelsById = <String, TdfLabel>{
      for (final label in finalLabels) label.id: label,
    };
    final knownScopedLabelIds = _resolveScopedLabelIds(
      postCascadeLabelsById: postCascadeLabelsById,
      primary: primary,
      secondary: secondary,
      baseline: baseline,
    );

    final evictedFromQueueIds = <String>{};
    final mutatedByNowTaskIds = <String>{
      ...extraRewrittenTaskIds,
      ...inlineRewrite.rewrittenTaskIds,
    };
    final tasksAfterLabelStrip =
        TaskBoardReconciler.stripDeletedLabelsAndValidateReferences(
          taskOutcome.liveTasks,
          validLabelIds,
          labelOutcome.deletedLabelsById,
          baseline?.labels,
          discardedLabelIds: labelOutcome.discardedIds,
          explicitlyDeletedLabelIds: labelOutcome.explicitlyDeletedIds,
          knownScopedLabelIds: knownScopedLabelIds,
          evictedFromQueueOut: evictedFromQueueIds,
          boards: boards,
          mutatedByNowCascadeOut: mutatedByNowTaskIds,
          now: now,
        );
    final tasksAfterLocStrip =
        TaskBoardReconciler.stripDeletedLocationsFromTasksAndValidate(
          tasksAfterLabelStrip,
          validLocationIds,
          locationOutcome.deletedLocationsById,
          baseline?.locations,
          postCascadeLabelsById,
          discardedLocationIds: locationOutcome.discardedIds,
          explicitlyDeletedLocationIds: locationOutcome.explicitlyDeletedIds,
          mutatedByNowCascadeOut: mutatedByNowTaskIds,
          now: now,
        );

    final uncleanedAfterCascadesById = _applyCascadesToUncleanedTasks(
      uncleanedTasks: taskOutcome.uncleanedLiveTasksById.values.toList(),
      validLabelIds: validLabelIds,
      deletedLabelsById: labelOutcome.deletedLabelsById,
      discardedLabelIds: labelOutcome.discardedIds,
      explicitlyDeletedLabelIds: labelOutcome.explicitlyDeletedIds,
      baselineLabels: baseline?.labels,
      knownScopedLabelIds: knownScopedLabelIds,
      boards: boards,
      validLocationIds: validLocationIds,
      deletedLocationsById: locationOutcome.deletedLocationsById,
      discardedLocationIds: locationOutcome.discardedIds,
      explicitlyDeletedLocationIds: locationOutcome.explicitlyDeletedIds,
      baselineLocations: baseline?.locations,
      postCascadeLabelsById: postCascadeLabelsById,
      now: now,
    );

    final openOnlyStripIds = <String>{
      ...taskOutcome.discardedTaskIds,
      ...taskOutcome.explicitlyDeletedTaskIds,
      ...extraDiscardedTaskIds,
      ...inlineRewrite.discardedTaskIds,
    };
    final tasksAfterOpenStrips = _stripOpenTaskDependenciesForIds(
      tasksAfterLocStrip,
      openOnlyStripIds,
      now,
      strippedTaskIdsOut: mutatedByNowTaskIds,
    );

    final leftGen = effectivePrimary.deletedBlock.generation;
    final rightGen = effectiveSecondary.deletedBlock.generation;
    final preTxLeftGen = preTransactionPrimaryGeneration ?? leftGen;
    final unincrementedBaseGen = preTxLeftGen >= rightGen
        ? preTxLeftGen
        : rightGen;
    final shouldPruneRetention =
        pruneExpiredDeleted && cleanupMode == TdfCleanupMode.finalStage;
    var finalizedDeleted = finalizeDeletedBlock(
      leftGen >= rightGen ? leftGen : rightGen,
      taskOutcome.deletedTasksById,
      labelOutcome.deletedLabelsById,
      locationOutcome.retiredByUndelete ||
          labelOutcome.retiredByUndelete ||
          taskOutcome.retiredByUndelete,
      shouldPruneRetention,
      now,
      locationOutcome.deletedLocationsById,
      unincrementedBaseGen,
    );
    var tasksAfterRetention = _stripExpiredTaskDependencies(
      tasksAfterOpenStrips,
      taskOutcome.deletedTasksById,
      finalizedDeleted,
      now,
      strippedTaskIdsOut: mutatedByNowTaskIds,
    );
    if (shouldPruneRetention && pruneExpiredCompleted) {
      final prunedResult = _pruneExpiredCompletedTasksIntoDeleted(
        tasksAfterRetention,
        finalizedDeleted,
        now,
      );
      tasksAfterRetention = prunedResult.survivingTasks;
      finalizedDeleted = prunedResult.deletedBlock;
    }

    final tasksAfterBlockCleanup = cleanupMode == TdfCleanupMode.finalStage
        ? TaskBoardEvaluator.cleanupResolvedTaskBlocks(
            tasks: tasksAfterRetention,
            deleted: finalizedDeleted,
            nowUtc: now,
            alreadyStampedTaskIds: <String>{
              ...allFreshlyRecoveredTaskIds,
              ...taskOutcome.undeletedTaskIds,
            },
          ).tasks
        : tasksAfterRetention;

    final finalTasks = _assignFinalMergedTaskRevisions(
      tasksAfterCleanup: tasksAfterBlockCleanup,
      reconciledLiveTasks: taskOutcome.liveTasks,
      uncleanedAfterCascadesById: uncleanedAfterCascadesById,
      undeletedTaskIds: taskOutcome.undeletedTaskIds,
      freshlyRecoveredTaskIds: allFreshlyRecoveredTaskIds,
      mutatedByNowTaskIds: mutatedByNowTaskIds,
      boards: boards,
      now: now,
      cleanupMode: cleanupMode,
    );

    final undeletedQueuedTaskIds = _resolveUndeletedQueuedTaskIds(
      effectivePrimary,
      effectiveSecondary,
      taskOutcome.undeletedTaskIds,
      evictedFromQueueIds,
    );
    final mergedQueue = mergeQueueBlocks(
      effectivePrimary,
      effectiveSecondary,
      baseline?.queueBlock,
      undeletedQueuedTaskIds,
      finalTasks,
      evictedFromQueueIds: evictedFromQueueIds,
    );

    validateMergedGraphAndBounds(
      finalTasks,
      finalLabels,
      locationOutcome.liveLocations,
      finalizedDeleted,
      mergedQueue,
    );

    final mergedBoard = TaskBoard.evaluate(
      tasks: finalTasks,
      evaluationTime: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
      labels: finalLabels,
      locations: locationOutcome.liveLocations,
      deletedBlock: finalizedDeleted,
      queueBlock: mergedQueue,
      pruneExpiredCompleted: false,
    );
    AppLogger.event(
      LogLevel.info,
      LogTag.sync,
      'sync.merge',
      fields: <String, Object?>{
        'mode': cleanupMode.name,
        'primary_tasks': primary.allTasks.length,
        'secondary_tasks': secondary.allTasks.length,
        'merged_tasks': mergedBoard.allTasks.length,
        'merged_labels': mergedBoard.labels.length,
        'merged_locations': mergedBoard.locations.length,
        'generation': mergedBoard.deletedBlock.generation,
      },
    );
    return mergedBoard;
  }

  /// Merges the `queue` blocks of [primary] and [secondary] with [baselineQueue] and reconciles against [mergedTasks] (`TDF-QSYNC-001`).
  static TdfQueueBlock mergeQueueBlocks(
    TaskBoard primary,
    TaskBoard secondary,
    TdfQueueBlock? baselineQueue,
    Set<String> undeletedTaskIds,
    List<TaskItem> mergedTasks, {
    Set<String> evictedFromQueueIds = const <String>{},
  }) {
    final primaryQueue = primary.queueBlock;
    final secondaryQueue = secondary.queueBlock;
    final openById = <String, TaskItem>{
      for (final task in mergedTasks)
        if (!task.isCompleted &&
            task.completedAt == null &&
            !evictedFromQueueIds.contains(task.id))
          task.id: task,
    };

    final primaryWins =
        TdfPayloadComparison.compareQueueBlocks(primaryQueue, secondaryQueue) >=
        0;
    final winnerQueue = primaryWins ? primaryQueue : secondaryQueue;
    final loserQueue = primaryWins ? secondaryQueue : primaryQueue;
    final winnerTasks = primaryWins ? primary.allTasks : secondary.allTasks;
    final winnerBoardIds = <String>{for (final task in winnerTasks) task.id};

    final sameAsPrimary =
        baselineQueue != null &&
        listEquals(primaryQueue.taskIds, baselineQueue.taskIds);
    final sameAsSecondary =
        baselineQueue != null &&
        listEquals(secondaryQueue.taskIds, baselineQueue.taskIds);
    final appendFromLoser =
        baselineQueue == null ||
        (!listEquals(primaryQueue.taskIds, secondaryQueue.taskIds) &&
            !sameAsPrimary &&
            !sameAsSecondary);
    final baseSelectedIds = appendFromLoser
        ? winnerQueue.taskIds
        : (sameAsPrimary ? secondaryQueue.taskIds : primaryQueue.taskIds);

    final seenInQueue = <String>{};
    final reconciledIds = <String>[
      for (final id in baseSelectedIds)
        if (openById.containsKey(id) && seenInQueue.add(id)) id,
    ];

    final baselineIdSet = baselineQueue?.taskIds.toSet() ?? winnerBoardIds;
    final candidateIds = appendFromLoser
        ? loserQueue.taskIds
        : <String>[...primaryQueue.taskIds, ...secondaryQueue.taskIds];
    final concurrentAdditions = <TaskItem>[];
    for (final id in candidateIds) {
      final task = openById[id];
      if (task == null || seenInQueue.contains(id)) {
        continue;
      }
      final isAddition =
          undeletedTaskIds.contains(id) ||
          (appendFromLoser && !baselineIdSet.contains(id));
      if (isAddition && seenInQueue.add(id)) {
        concurrentAdditions.add(task);
      }
    }

    concurrentAdditions.sort(_compareConcurrentQueuedTasks);
    reconciledIds.addAll(concurrentAdditions.map((task) => task.id));
    if (reconciledIds.length > TdfQueueBlock.maxQueueEntries) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged queue block exceeds MAX_QUEUE_ENTRIES ($maxTdfQueueEntries).',
      );
    }

    var greatestQueue = winnerQueue;
    if (baselineQueue != null &&
        TdfPayloadComparison.compareQueueBlocks(baselineQueue, greatestQueue) >
            0) {
      greatestQueue = baselineQueue;
    }
    if (listEquals(greatestQueue.taskIds, reconciledIds)) {
      AppLogger.event(
        LogLevel.debug,
        LogTag.sync,
        'sync.reconcile.queue',
        fields: <String, Object?>{
          'winner': primaryWins ? 'primary' : 'secondary',
          'entries': reconciledIds.length,
          'additions': concurrentAdditions.length,
        },
      );
      return TdfQueueBlock(
        modifiedAt: greatestQueue.modifiedAt,
        taskIds: reconciledIds,
      );
    }

    var maxModified = primaryQueue.modifiedAt.isAfter(secondaryQueue.modifiedAt)
        ? primaryQueue.modifiedAt
        : secondaryQueue.modifiedAt;
    if (baselineQueue != null &&
        baselineQueue.modifiedAt.isAfter(maxModified)) {
      maxModified = baselineQueue.modifiedAt;
    }
    final nextModified = maxModified.add(const Duration(seconds: 1));
    if (!TdfCalendar.isWithinTimestampBounds(nextModified)) {
      _throwTdf(
        TdfErrorKind.invalidTimestamp,
        'Merged queue revision exceeds maximum supported timestamp.',
      );
    }
    AppLogger.event(
      LogLevel.debug,
      LogTag.sync,
      'sync.reconcile.queue',
      fields: <String, Object?>{
        'winner': primaryWins ? 'primary' : 'secondary',
        'entries': reconciledIds.length,
        'additions': concurrentAdditions.length,
      },
    );
    return TdfQueueBlock(modifiedAt: nextModified, taskIds: reconciledIds);
  }

  /// Resolves `RecoveryRequired` entities from [localBoard] into [sharedBoard] using `discard` or `recoverAsNew` (`TDF-REC-002`).
  static TaskBoard recoverAmbiguousEntities({
    required TaskBoard localBoard,
    required TaskBoard sharedBoard,
    TaskBoard? baseline,
    Iterable<String> recoverTaskIds = const <String>[],
    Iterable<String> recoverLabelIds = const <String>[],
    Iterable<String> recoverLocationIds = const <String>[],
    Map<String, TdfRecoveryResolution> taskRecoveryResolutions = const {},
    Map<String, TdfRecoveryResolution> labelRecoveryResolutions = const {},
    Map<String, TdfRecoveryResolution> locationRecoveryResolutions = const {},
    required DateTime evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
    TdfCleanupMode cleanupMode = TdfCleanupMode.finalStage,
    bool pruneExpiredDeleted = true,
    bool pruneExpiredCompleted = true,
  }) {
    final now = TaskItem.normalizeTimestamp(evaluationTime);
    final effectiveRecoverLocs = _resolveRecoverIdSet(
      recoverLocationIds,
      locationRecoveryResolutions,
    );
    final effectiveRecoverLabels = _resolveRecoverIdSet(
      recoverLabelIds,
      labelRecoveryResolutions,
    );
    final effectiveRecoverTasks = _resolveRecoverIdSet(
      recoverTaskIds,
      taskRecoveryResolutions,
    );

    final prepared = _prepareBoardForRecovery(
      staleBoard: localBoard,
      advancedBoard: sharedBoard,
      baseline: baseline,
      recoverLocationIds: effectiveRecoverLocs,
      recoverLabelIds: effectiveRecoverLabels,
      recoverTaskIds: effectiveRecoverTasks,
      discardAllUnrecoveredStaleOnly: true,
      now: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
    );

    return merge(
      primary: prepared.board,
      secondary: sharedBoard,
      baseline: baseline,
      acknowledgedGeneration: sharedBoard.deletedBlock.generation,
      extraFreshlyRecoveredTaskIds: prepared.freshlyRecoveredTaskIds,
      extraRewrittenLabelIds: prepared.rewrittenLabelIds,
      extraRewrittenTaskIds: prepared.rewrittenTaskIds,
      extraDiscardedTaskIds: prepared.discardedTaskIds,
      evaluationTime: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
      cleanupMode: cleanupMode,
      pruneExpiredDeleted: pruneExpiredDeleted,
      pruneExpiredCompleted: pruneExpiredCompleted,
    );
  }

  /// Evaluates the 6-tier pipeline on [board] at [evaluationTime], applying `TDF-PUB-004` retention pruning and `TDF-CLEAN-001` only in `TdfCleanupMode.finalStage`.
  static TaskBoard stampAndNormalize(
    TaskBoard board, {
    required DateTime evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
    TdfCleanupMode cleanupMode = TdfCleanupMode.finalStage,
    bool pruneExpiredDeleted = true,
    bool pruneExpiredCompleted = true,
    int? preTransactionGeneration,
  }) => stampAndNormalizeWithStatus(
    board,
    evaluationTime: evaluationTime,
    localEvaluationTime: localEvaluationTime,
    timeZone: timeZone,
    dueLeadWindow: dueLeadWindow,
    cleanupMode: cleanupMode,
    pruneExpiredDeleted: pruneExpiredDeleted,
    pruneExpiredCompleted: pruneExpiredCompleted,
    preTransactionGeneration: preTransactionGeneration,
  ).board;

  /// Normalizes [board] at [evaluationTime], returning both the evaluated board and whether any persisted TDF document content changed.
  static ({TaskBoard board, bool documentChanged}) stampAndNormalizeWithStatus(
    TaskBoard board, {
    required DateTime evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
    TdfCleanupMode cleanupMode = TdfCleanupMode.finalStage,
    bool pruneExpiredDeleted = true,
    bool pruneExpiredCompleted = true,
    int? preTransactionGeneration,
  }) {
    final normalizedNow = TaskItem.normalizeTimestamp(evaluationTime);
    final isFinalStage = cleanupMode == TdfCleanupMode.finalStage;
    if (!isFinalStage) {
      return (
        board: TaskBoard.evaluate(
          tasks: board.allTasks,
          evaluationTime: normalizedNow,
          localEvaluationTime: localEvaluationTime,
          timeZone: timeZone,
          dueLeadWindow: dueLeadWindow,
          labels: board.labels,
          locations: board.locations,
          deletedBlock: board.deletedBlock,
          queueBlock: board.queueBlock,
          pruneExpiredCompleted: false,
        ),
        documentChanged: false,
      );
    }

    var finalizedDeleted = board.deletedBlock;
    var tasksAfterRetention = board.allTasks;
    var documentChanged = false;
    final strippedByRetentionIds = <String>{};
    if (pruneExpiredDeleted &&
        (board.deletedBlock.tasks.isNotEmpty ||
            board.deletedBlock.labels.isNotEmpty ||
            board.deletedBlock.locations.isNotEmpty)) {
      final deletedTasksById = <String, TdfDeletedTaskRecord>{
        for (final record in board.deletedBlock.tasks) record.taskId: record,
      };
      final deletedLabelsById = <String, TdfDeletedLabelRecord>{
        for (final record in board.deletedBlock.labels) record.labelId: record,
      };
      final deletedLocationsById = <String, TdfDeletedLocationRecord>{
        for (final record in board.deletedBlock.locations)
          record.locationId: record,
      };
      finalizedDeleted = finalizeDeletedBlock(
        board.deletedBlock.generation,
        deletedTasksById,
        deletedLabelsById,
        false,
        true,
        normalizedNow,
        deletedLocationsById,
        preTransactionGeneration,
      );
      tasksAfterRetention = _stripExpiredTaskDependencies(
        tasksAfterRetention,
        deletedTasksById,
        finalizedDeleted,
        normalizedNow,
        strippedTaskIdsOut: strippedByRetentionIds,
      );
      if (finalizedDeleted != board.deletedBlock ||
          strippedByRetentionIds.isNotEmpty) {
        documentChanged = true;
      }
    }
    if (pruneExpiredCompleted) {
      final prunedResult = _pruneExpiredCompletedTasksIntoDeleted(
        tasksAfterRetention,
        finalizedDeleted,
        normalizedNow,
      );
      if (prunedResult.survivingTasks.length != tasksAfterRetention.length ||
          prunedResult.deletedBlock != finalizedDeleted) {
        documentChanged = true;
      }
      tasksAfterRetention = prunedResult.survivingTasks;
      finalizedDeleted = prunedResult.deletedBlock;
    }
    final cleaned = TaskBoardEvaluator.cleanupResolvedTaskBlocks(
      tasks: tasksAfterRetention,
      deleted: finalizedDeleted,
      nowUtc: normalizedNow,
      alreadyStampedTaskIds: strippedByRetentionIds,
    );
    if (cleaned.cleanedSuspendedCount > 0 || cleaned.cleanedBlockedCount > 0) {
      documentChanged = true;
    }
    validateMergedGraphAndBounds(
      cleaned.tasks,
      board.labels,
      board.locations,
      finalizedDeleted,
      board.queueBlock,
    );
    return (
      board: TaskBoard.evaluate(
        tasks: cleaned.tasks,
        evaluationTime: normalizedNow,
        localEvaluationTime: localEvaluationTime,
        timeZone: timeZone,
        dueLeadWindow: dueLeadWindow,
        labels: board.labels,
        locations: board.locations,
        deletedBlock: finalizedDeleted,
        queueBlock: board.queueBlock,
        pruneExpiredCompleted: false,
      ),
      documentChanged: documentChanged,
    );
  }

  /// Validates the combined dependency graph for cycles and checks `TDF-PUB-001` / `TDF-VAL-002` resource bounds.
  static void validateMergedGraphAndBounds(
    List<TaskItem> tasks,
    List<TdfLabel> labels, [
    List<TdfLocation> locations = const <TdfLocation>[],
    TdfDeletedBlock? deletedBlock,
    TdfQueueBlock? queueBlock,
  ]) {
    if (locations.length > maxTdfLocations) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged document exceeds MAX_LOCATIONS ($maxTdfLocations).',
      );
    }
    final totalBlocks = _computeCanonicalBlockCount(
      tasks: tasks,
      labels: labels,
      locations: locations,
      deletedBlock: deletedBlock,
      queueBlock: queueBlock,
    );
    if (totalBlocks > maxTdfBlocksPerDoc) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged document exceeds MAX_BLOCKS_PER_DOC ($maxTdfBlocksPerDoc).',
      );
    }
    for (final location in locations) {
      _validateLocationBounds(location);
    }
    for (final label in labels) {
      _validateLabelBounds(label);
    }
    for (final task in tasks) {
      _validateTaskBounds(task);
    }
    final taskMap = <String, TaskItem>{for (final task in tasks) task.id: task};
    if (_hasDependencyCycle(taskMap)) {
      _throwTdf(
        TdfErrorKind.circularDependency,
        'Merged document contains a circular task dependency.',
      );
    }
  }

  /// Accumulates a single [rule] into mutable condition statement counters.
  static ({
    bool globalAny,
    bool dayReset,
    bool timeReset,
    bool locReset,
    int dayCount,
    int timeCount,
    bool hasLocIds,
    int legacyLocCount,
  })
  _accumulateConditionRule(
    TaskCondition rule,
    ({
      bool globalAny,
      bool dayReset,
      bool timeReset,
      bool locReset,
      int dayCount,
      int timeCount,
      bool hasLocIds,
      int legacyLocCount,
    })
    state,
  ) {
    return switch (rule) {
      GlobalResetTaskCondition() => (
        globalAny: true,
        dayReset: state.dayReset,
        timeReset: state.timeReset,
        locReset: state.locReset,
        dayCount: state.dayCount,
        timeCount: state.timeCount,
        hasLocIds: state.hasLocIds,
        legacyLocCount: state.legacyLocCount,
      ),
      GroupResetTaskCondition(:final targetGroup) => switch (targetGroup) {
        ConditionGroup.day => (
          globalAny: state.globalAny,
          dayReset: true,
          timeReset: state.timeReset,
          locReset: state.locReset,
          dayCount: state.dayCount,
          timeCount: state.timeCount,
          hasLocIds: state.hasLocIds,
          legacyLocCount: state.legacyLocCount,
        ),
        ConditionGroup.time => (
          globalAny: state.globalAny,
          dayReset: state.dayReset,
          timeReset: true,
          locReset: state.locReset,
          dayCount: state.dayCount,
          timeCount: state.timeCount,
          hasLocIds: state.hasLocIds,
          legacyLocCount: state.legacyLocCount,
        ),
        ConditionGroup.location => (
          globalAny: state.globalAny,
          dayReset: state.dayReset,
          timeReset: state.timeReset,
          locReset: true,
          dayCount: state.dayCount,
          timeCount: state.timeCount,
          hasLocIds: state.hasLocIds,
          legacyLocCount: state.legacyLocCount,
        ),
      },
      DayTaskCondition() => (
        globalAny: state.globalAny,
        dayReset: state.dayReset,
        timeReset: state.timeReset,
        locReset: state.locReset,
        dayCount: state.dayCount + 1,
        timeCount: state.timeCount,
        hasLocIds: state.hasLocIds,
        legacyLocCount: state.legacyLocCount,
      ),
      TimeWindowTaskCondition() => (
        globalAny: state.globalAny,
        dayReset: state.dayReset,
        timeReset: state.timeReset,
        locReset: state.locReset,
        dayCount: state.dayCount,
        timeCount: state.timeCount + 1,
        hasLocIds: state.hasLocIds,
        legacyLocCount: state.legacyLocCount,
      ),
      LocationTaskCondition() => (
        globalAny: state.globalAny,
        dayReset: state.dayReset,
        timeReset: state.timeReset,
        locReset: state.locReset,
        dayCount: state.dayCount,
        timeCount: state.timeCount,
        hasLocIds: state.hasLocIds || rule.locationIds.isNotEmpty,
        legacyLocCount:
            state.legacyLocCount + (rule.locationIds.isEmpty ? 1 : 0),
      ),
    };
  }

  /// Advances `modifiedAt` via `TDF-MUT-002` on any surviving label in [labels] whose references were rewritten in [rewrittenLabelIds].
  static List<TdfLabel> _advanceRewrittenLabels(
    List<TdfLabel> labels,
    Set<String> rewrittenLabelIds,
    DateTime now,
  ) {
    if (rewrittenLabelIds.isEmpty) {
      return labels;
    }
    return <TdfLabel>[
      for (final label in labels)
        if (rewrittenLabelIds.contains(label.id))
          label.copyWith(
            modifiedAt: TaskItem.nextModifiedTimestamp(
              now,
              label.effectiveModifiedAt,
            ),
          )
        else
          label,
    ];
  }

  /// Applies `TDF-MERGE-011` label and location deletion cascades to [uncleanedTasks] for `TDF-MERGE-004` comparison.
  static Map<String, TaskItem> _applyCascadesToUncleanedTasks({
    required List<TaskItem> uncleanedTasks,
    required Set<String> validLabelIds,
    required Map<String, TdfDeletedLabelRecord> deletedLabelsById,
    required Set<String> discardedLabelIds,
    required Set<String> explicitlyDeletedLabelIds,
    required List<TdfLabel>? baselineLabels,
    required Set<String> knownScopedLabelIds,
    required (TaskBoard, TaskBoard, TaskBoard?) boards,
    required Set<String> validLocationIds,
    required Map<String, TdfDeletedLocationRecord> deletedLocationsById,
    required Set<String> discardedLocationIds,
    required Set<String> explicitlyDeletedLocationIds,
    required List<TdfLocation>? baselineLocations,
    required Map<String, TdfLabel> postCascadeLabelsById,
    required DateTime now,
  }) {
    if (uncleanedTasks.isEmpty) {
      return const <String, TaskItem>{};
    }
    final afterLabels =
        TaskBoardReconciler.stripDeletedLabelsAndValidateReferences(
          uncleanedTasks,
          validLabelIds,
          deletedLabelsById,
          baselineLabels,
          discardedLabelIds: discardedLabelIds,
          explicitlyDeletedLabelIds: explicitlyDeletedLabelIds,
          knownScopedLabelIds: knownScopedLabelIds,
          boards: boards,
          now: now,
        );
    final afterLocations =
        TaskBoardReconciler.stripDeletedLocationsFromTasksAndValidate(
          afterLabels,
          validLocationIds,
          deletedLocationsById,
          baselineLocations,
          postCascadeLabelsById,
          discardedLocationIds: discardedLocationIds,
          explicitlyDeletedLocationIds: explicitlyDeletedLocationIds,
          now: now,
        );
    return <String, TaskItem>{for (final task in afterLocations) task.id: task};
  }

  /// Rewrites `recoverAsNew` entities on the stale side when inline recovery resolutions are passed directly to [merge].
  static ({
    TaskBoard primary,
    TaskBoard secondary,
    Set<String> freshlyRecoveredLocationIds,
    Set<String> freshlyRecoveredLabelIds,
    Set<String> freshlyRecoveredTaskIds,
    Set<String> rewrittenLabelIds,
    Set<String> rewrittenTaskIds,
    Set<String> discardedTaskIds,
  })
  _applyInlineRecoveryRewrite({
    required TaskBoard primary,
    required TaskBoard secondary,
    required TaskBoard? baseline,
    required bool primaryRefresh,
    required bool secondaryRefresh,
    required Map<String, TdfRecoveryResolution> taskRecoveryResolutions,
    required Map<String, TdfRecoveryResolution> labelRecoveryResolutions,
    required Map<String, TdfRecoveryResolution> locationRecoveryResolutions,
    required DateTime now,
    required DateTime? localEvaluationTime,
    required TdfTimeZoneContext? timeZone,
    required Duration? dueLeadWindow,
  }) {
    final hasNewTask = _hasAnyRecoverAsNew(taskRecoveryResolutions);
    final hasNewLabel = _hasAnyRecoverAsNew(labelRecoveryResolutions);
    final hasNewLocation = _hasAnyRecoverAsNew(locationRecoveryResolutions);
    if (!hasNewTask && !hasNewLabel && !hasNewLocation) {
      return (
        primary: primary,
        secondary: secondary,
        freshlyRecoveredLocationIds: const <String>{},
        freshlyRecoveredLabelIds: const <String>{},
        freshlyRecoveredTaskIds: const <String>{},
        rewrittenLabelIds: const <String>{},
        rewrittenTaskIds: const <String>{},
        discardedTaskIds: const <String>{},
      );
    }
    final recoverLocs = _resolveRecoverIdSet(
      const <String>[],
      locationRecoveryResolutions,
    );
    final recoverLabels = _resolveRecoverIdSet(
      const <String>[],
      labelRecoveryResolutions,
    );
    final recoverTasks = _resolveRecoverIdSet(
      const <String>[],
      taskRecoveryResolutions,
    );
    var currentPrimary = primary;
    var currentSecondary = secondary;
    final freshlyRecoveredLocationIds = <String>{};
    final freshlyRecoveredLabelIds = <String>{};
    final freshlyRecoveredTaskIds = <String>{};
    final rewrittenLabelIds = <String>{};
    final rewrittenTaskIds = <String>{};
    final discardedTaskIds = <String>{};

    if (primaryRefresh) {
      final prepared = _prepareBoardForRecovery(
        staleBoard: currentPrimary,
        advancedBoard: currentSecondary,
        baseline: baseline,
        recoverLocationIds: recoverLocs,
        recoverLabelIds: recoverLabels,
        recoverTaskIds: recoverTasks,
        discardAllUnrecoveredStaleOnly: false,
        explicitTaskResolutions: taskRecoveryResolutions,
        explicitLabelResolutions: labelRecoveryResolutions,
        explicitLocationResolutions: locationRecoveryResolutions,
        now: now,
        localEvaluationTime: localEvaluationTime,
        timeZone: timeZone,
        dueLeadWindow: dueLeadWindow,
      );
      currentPrimary = prepared.board;
      freshlyRecoveredLocationIds.addAll(prepared.freshlyRecoveredLocationIds);
      freshlyRecoveredLabelIds.addAll(prepared.freshlyRecoveredLabelIds);
      freshlyRecoveredTaskIds.addAll(prepared.freshlyRecoveredTaskIds);
      rewrittenLabelIds.addAll(prepared.rewrittenLabelIds);
      rewrittenTaskIds.addAll(prepared.rewrittenTaskIds);
      discardedTaskIds.addAll(prepared.discardedTaskIds);
    }
    if (secondaryRefresh) {
      final prepared = _prepareBoardForRecovery(
        staleBoard: currentSecondary,
        advancedBoard: currentPrimary,
        baseline: baseline,
        recoverLocationIds: recoverLocs,
        recoverLabelIds: recoverLabels,
        recoverTaskIds: recoverTasks,
        discardAllUnrecoveredStaleOnly: false,
        explicitTaskResolutions: taskRecoveryResolutions,
        explicitLabelResolutions: labelRecoveryResolutions,
        explicitLocationResolutions: locationRecoveryResolutions,
        now: now,
        localEvaluationTime: localEvaluationTime,
        timeZone: timeZone,
        dueLeadWindow: dueLeadWindow,
      );
      currentSecondary = prepared.board;
      freshlyRecoveredLocationIds.addAll(prepared.freshlyRecoveredLocationIds);
      freshlyRecoveredLabelIds.addAll(prepared.freshlyRecoveredLabelIds);
      freshlyRecoveredTaskIds.addAll(prepared.freshlyRecoveredTaskIds);
      rewrittenLabelIds.addAll(prepared.rewrittenLabelIds);
      rewrittenTaskIds.addAll(prepared.rewrittenTaskIds);
      discardedTaskIds.addAll(prepared.discardedTaskIds);
    }
    return (
      primary: currentPrimary,
      secondary: currentSecondary,
      freshlyRecoveredLocationIds: freshlyRecoveredLocationIds,
      freshlyRecoveredLabelIds: freshlyRecoveredLabelIds,
      freshlyRecoveredTaskIds: freshlyRecoveredTaskIds,
      rewrittenLabelIds: rewrittenLabelIds,
      rewrittenTaskIds: rewrittenTaskIds,
      discardedTaskIds: discardedTaskIds,
    );
  }

  /// Assigns deterministic `TDF-MERGE-004` revisions across [tasksAfterCleanup].
  static List<TaskItem> _assignFinalMergedTaskRevisions({
    required List<TaskItem> tasksAfterCleanup,
    required List<TaskItem> reconciledLiveTasks,
    required Map<String, TaskItem> uncleanedAfterCascadesById,
    required Set<String> undeletedTaskIds,
    required Set<String> freshlyRecoveredTaskIds,
    required Set<String> mutatedByNowTaskIds,
    required (TaskBoard, TaskBoard, TaskBoard?) boards,
    required DateTime now,
    required TdfCleanupMode cleanupMode,
  }) {
    final (primary, secondary, baseline) = boards;
    final primaryById = <String, TaskItem>{
      for (final task in primary.allTasks) task.id: task,
    };
    final secondaryById = <String, TaskItem>{
      for (final task in secondary.allTasks) task.id: task,
    };
    final baselineById = <String, TaskItem>{
      if (baseline != null)
        for (final task in baseline.allTasks) task.id: task,
    };
    final reconciledById = <String, TaskItem>{
      for (final task in reconciledLiveTasks) task.id: task,
    };

    return <TaskItem>[
      for (final task in tasksAfterCleanup)
        _assignSingleFinalTaskRevision(
          finalTask: task,
          reconciledTask: reconciledById[task.id],
          uncleanedTask: uncleanedAfterCascadesById[task.id],
          primaryTask: primaryById[task.id],
          secondaryTask: secondaryById[task.id],
          baselineTask: baselineById[task.id],
          wasUndeleted: undeletedTaskIds.contains(task.id),
          wasFreshlyRecovered: freshlyRecoveredTaskIds.contains(task.id),
          mutatedByNowStrip: mutatedByNowTaskIds.contains(task.id),
          now: now,
          cleanupMode: cleanupMode,
        ),
    ];
  }

  /// Assigns the final `TDF-MERGE-004` / `TDF-MUT-002` `modifiedAt` timestamp for a single surviving [finalTask].
  static TaskItem _assignSingleFinalTaskRevision({
    required TaskItem finalTask,
    required TaskItem? reconciledTask,
    required TaskItem? uncleanedTask,
    required TaskItem? primaryTask,
    required TaskItem? secondaryTask,
    required TaskItem? baselineTask,
    required bool wasUndeleted,
    required bool wasFreshlyRecovered,
    required bool mutatedByNowStrip,
    required DateTime now,
    required TdfCleanupMode cleanupMode,
  }) {
    if (wasUndeleted) {
      final baseDecision = reconciledTask?.effectiveModifiedAt ?? now;
      if (mutatedByNowStrip && now.isAfter(baseDecision)) {
        return finalTask.copyWith(modifiedAt: _checkedTimestamp(now));
      }
      return finalTask.copyWith(modifiedAt: _checkedTimestamp(baseDecision));
    }

    if (primaryTask != null && secondaryTask != null) {
      final winner =
          TdfPayloadComparison.compareTaskVersions(
                primaryTask,
                secondaryTask,
              ) >=
              0
          ? primaryTask
          : secondaryTask;
      final referenceExisting =
          (baselineTask != null &&
              TdfPayloadComparison.compareTaskVersions(baselineTask, winner) >
                  0)
          ? baselineTask
          : winner;
      var maxObserved = _laterDate(
        primaryTask.effectiveModifiedAt,
        secondaryTask.effectiveModifiedAt,
      );
      maxObserved = _laterDate(maxObserved, baselineTask?.effectiveModifiedAt);

      if (mutatedByNowStrip) {
        final bumpedStrip = _checkedBumpPlusOneSecond(maxObserved);
        final withNowStrip = now.isAfter(bumpedStrip) ? now : bumpedStrip;
        return finalTask.copyWith(modifiedAt: _checkedTimestamp(withNowStrip));
      }

      if (referenceExisting.completions == finalTask.completions &&
          TdfPayloadComparison.compareTaskPayloads(
                referenceExisting,
                finalTask,
              ) ==
              0) {
        return finalTask.copyWith(
          modifiedAt: referenceExisting.modifiedAt,
          clearModifiedAt: referenceExisting.modifiedAt == null,
        );
      }

      final bumped = _checkedBumpPlusOneSecond(maxObserved);
      if (cleanupMode == TdfCleanupMode.deferred ||
          (uncleanedTask != null &&
              TdfPayloadComparison.compareTaskPayloads(
                    finalTask,
                    uncleanedTask,
                  ) ==
                  0)) {
        return finalTask.copyWith(modifiedAt: bumped);
      }
      final withNow = now.isAfter(bumped) ? now : bumped;
      return finalTask.copyWith(modifiedAt: _checkedTimestamp(withNow));
    }

    final sourceTask = primaryTask ?? secondaryTask;
    if (sourceTask == null) {
      return finalTask;
    }
    if (wasFreshlyRecovered) {
      return finalTask.copyWith(
        modifiedAt: _checkedTimestamp(sourceTask.effectiveModifiedAt),
      );
    }
    if (mutatedByNowStrip) {
      final bumpedStrip = _checkedBumpPlusOneSecond(
        sourceTask.effectiveModifiedAt,
      );
      final withNowStrip = now.isAfter(bumpedStrip) ? now : bumpedStrip;
      return finalTask.copyWith(modifiedAt: _checkedTimestamp(withNowStrip));
    }
    if (sourceTask.completions == finalTask.completions &&
        TdfPayloadComparison.compareTaskPayloads(sourceTask, finalTask) == 0) {
      return finalTask.copyWith(
        modifiedAt: sourceTask.modifiedAt,
        clearModifiedAt: sourceTask.modifiedAt == null,
      );
    }
    final bumped = _checkedBumpPlusOneSecond(sourceTask.effectiveModifiedAt);
    if (cleanupMode == TdfCleanupMode.deferred ||
        (uncleanedTask != null &&
            TdfPayloadComparison.compareTaskPayloads(
                  finalTask,
                  uncleanedTask,
                ) ==
                0)) {
      return finalTask.copyWith(modifiedAt: bumped);
    }
    final withNow = now.isAfter(bumped) ? now : bumped;
    return finalTask.copyWith(modifiedAt: _checkedTimestamp(withNow));
  }

  /// Adds one second to [timestamp] and validates calendar bounds.
  static DateTime _checkedBumpPlusOneSecond(DateTime timestamp) =>
      _checkedTimestamp(timestamp.add(const Duration(seconds: 1)));

  /// Verifies that [timestamp] lies within supported TDF calendar bounds.
  static DateTime _checkedTimestamp(DateTime timestamp) {
    if (!TdfCalendar.isWithinTimestampBounds(timestamp)) {
      _throwTdf(
        TdfErrorKind.invalidTimestamp,
        'Merged revision exceeds maximum supported timestamp.',
      );
    }
    return timestamp;
  }

  /// Collects `<location-id>` tokens from [conditions] into [target].
  static void _collectBoardLocationRefIds(
    List<TaskCondition> conditions,
    Set<String> target,
  ) {
    for (final rule in conditions) {
      if (rule is LocationTaskCondition && rule.locationIds.isNotEmpty) {
        target.addAll(rule.locationIds);
      }
    }
  }

  /// Collects referenced task, label, and location IDs across [board] into [usedTaskIds], [usedLabelIds], and [usedLocationIds].
  static void _collectBoardTaskAndLabelRefIds(
    TaskBoard board,
    Set<String> usedTaskIds,
    Set<String> usedLabelIds,
    Set<String> usedLocationIds,
  ) {
    for (final location in board.locations) {
      usedLocationIds.add(location.id);
    }
    for (final record in board.deletedBlock.locations) {
      usedLocationIds.add(record.locationId);
    }
    for (final label in board.labels) {
      usedLabelIds.add(label.id);
      _collectBoardLocationRefIds(label.conditions, usedLocationIds);
    }
    for (final record in board.deletedBlock.labels) {
      usedLabelIds.add(record.labelId);
    }
    for (final task in board.allTasks) {
      usedTaskIds.add(task.id);
      usedLabelIds.addAll(task.labelIds);
      _collectDependencyTargetIds(task.dependencies, usedTaskIds);
      _collectBoardLocationRefIds(task.conditions, usedLocationIds);
    }
    for (final record in board.deletedBlock.tasks) {
      usedTaskIds.add(record.taskId);
    }
    usedTaskIds.addAll(board.queueBlock.taskIds);
  }

  /// Collects prerequisite `<task-id>` targets from [dependencies] into [target].
  static void _collectDependencyTargetIds(
    List<TdfTaskDependency> dependencies,
    Set<String> target,
  ) {
    for (final dependency in dependencies) {
      target.add(dependency.taskId);
    }
  }

  /// Collects collision-free ID sets across [staleBoard], [advancedBoard], and [baseline] (`TDF-ID-001` Step 4).
  static ({Set<String> locations, Set<String> labels, Set<String> tasks})
  _collectUsedIdsForRecovery(
    TaskBoard staleBoard,
    TaskBoard advancedBoard,
    TaskBoard? baseline,
  ) {
    final usedLocations = <String>{};
    final usedLabels = <String>{};
    final usedTasks = <String>{};
    _collectBoardTaskAndLabelRefIds(
      staleBoard,
      usedTasks,
      usedLabels,
      usedLocations,
    );
    _collectBoardTaskAndLabelRefIds(
      advancedBoard,
      usedTasks,
      usedLabels,
      usedLocations,
    );
    if (baseline != null) {
      _collectBoardTaskAndLabelRefIds(
        baseline,
        usedTasks,
        usedLabels,
        usedLocations,
      );
    }
    return (locations: usedLocations, labels: usedLabels, tasks: usedTasks);
  }

  /// Orders concurrent queue additions by ascending UTC `createdAt`, then ascending ASCII `id` (`TDF-QSYNC-001`).
  static int _compareConcurrentQueuedTasks(TaskItem left, TaskItem right) {
    final createdCmp = left.createdAt.compareTo(right.createdAt);
    return createdCmp != 0 ? createdCmp : left.id.compareTo(right.id);
  }

  /// Counts total canonical blocks (`task`, `label`, `location`, `deleted`, `queue`, `subtasks`, `condition`) for `MAX_BLOCKS_PER_DOC`.
  static int _computeCanonicalBlockCount({
    required List<TaskItem> tasks,
    required List<TdfLabel> labels,
    required List<TdfLocation> locations,
    required TdfDeletedBlock? deletedBlock,
    required TdfQueueBlock? queueBlock,
  }) {
    var total = tasks.length + labels.length + locations.length;
    if (deletedBlock != null && !deletedBlock.isDefaultEmpty) {
      total++;
    }
    if (queueBlock != null && !queueBlock.isDefaultEmpty) {
      total++;
    }
    for (final label in labels) {
      total += _computeConditionRuleAndBlockCounts(label.conditions).subBlocks;
    }
    for (final task in tasks) {
      if (task.subtasks.isNotEmpty) {
        total++;
      }
      total += _computeConditionRuleAndBlockCounts(task.conditions).subBlocks;
    }
    return total;
  }

  /// Computes canonical condition statement count and emitted `condition { ... }` sub-block count (`0` or `1`).
  static ({int ruleStatements, int subBlocks})
  _computeConditionRuleAndBlockCounts(List<TaskCondition> conditions) {
    if (conditions.isEmpty) {
      return (ruleStatements: 0, subBlocks: 0);
    }
    var state = (
      globalAny: false,
      dayReset: false,
      timeReset: false,
      locReset: false,
      dayCount: 0,
      timeCount: 0,
      hasLocIds: false,
      legacyLocCount: 0,
    );
    for (final rule in conditions) {
      state = _accumulateConditionRule(rule, state);
    }
    if (state.globalAny) {
      return (ruleStatements: 1, subBlocks: 0);
    }
    final canonicalRuleCount =
        (state.dayReset ? 1 : state.dayCount) +
        (state.timeReset ? 1 : state.timeCount) +
        (state.locReset
            ? 1
            : ((state.hasLocIds ? 1 : 0) + state.legacyLocCount));
    return (
      ruleStatements: canonicalRuleCount,
      subBlocks: canonicalRuleCount >= 2 ? 1 : 0,
    );
  }

  /// Computes $D^{\text{label}}_X$ for [side] (`TDF-MERGE-006`).
  static Set<String> _computeDeletedLabelsForSide({
    required TaskBoard side,
    required TaskBoard? baseline,
    required bool isSideRefresh,
  }) {
    final sideLiveIds = <String>{for (final label in side.labels) label.id};
    return <String>{
      for (final record in side.deletedBlock.labels) record.labelId,
      if (baseline != null && !isSideRefresh)
        for (final baseLabel in baseline.labels)
          if (!sideLiveIds.contains(baseLabel.id)) baseLabel.id,
    };
  }

  /// Counts total `<location-id>` references across all `LocationTaskCondition` rules in [conditions].
  static int _countLocationRefs(List<TaskCondition> conditions) {
    var count = 0;
    for (final rule in conditions) {
      if (rule is LocationTaskCondition) {
        count += rule.locationIds.length;
      }
    }
    return count;
  }

  /// Filters superseded acknowledged tombstones out of [staleDeleted] before adopting [advancedBoard]'s generation (`TDF-REC-001` Step 4).
  static TdfDeletedBlock _filterStaleDeletedBlockForRecovery({
    required TdfDeletedBlock staleDeleted,
    required TaskBoard advancedBoard,
    required TdfDeletedBlock? baselineDeleted,
    required DateTime now,
  }) {
    final advancedTaskIds = <String>{
      for (final task in advancedBoard.allTasks) task.id,
    };
    final advancedLabelIds = <String>{
      for (final label in advancedBoard.labels) label.id,
    };
    final advancedLocationIds = <String>{
      for (final location in advancedBoard.locations) location.id,
    };
    final retainedTasks = <TdfDeletedTaskRecord>[
      for (final record in staleDeleted.tasks)
        if (baselineDeleted != null
            ? !_isAckedTask(record, baselineDeleted, true)
            : (!advancedTaskIds.contains(record.taskId) &&
                  !_isDeletedRecordExpired(record.deletedAt, now, true)))
          record,
    ];
    final retainedLabels = <TdfDeletedLabelRecord>[
      for (final record in staleDeleted.labels)
        if (baselineDeleted != null
            ? !_isAckedLabel(record, baselineDeleted, true)
            : (!advancedLabelIds.contains(record.labelId) &&
                  !_isDeletedRecordExpired(record.deletedAt, now, true)))
          record,
    ];
    final retainedLocations = <TdfDeletedLocationRecord>[
      for (final record in staleDeleted.locations)
        if (baselineDeleted != null
            ? !_isAckedLocation(record, baselineDeleted, true)
            : (!advancedLocationIds.contains(record.locationId) &&
                  !_isDeletedRecordExpired(record.deletedAt, now, true)))
          record,
    ];
    return TdfDeletedBlock(
      generation: advancedBoard.deletedBlock.generation,
      tasks: retainedTasks,
      labels: retainedLabels,
      locations: retainedLocations,
    );
  }

  /// Returns whether [resolutions] contains at least one [TdfRecoveryResolution.recoverAsNew] entry.
  static bool _hasAnyRecoverAsNew(
    Map<String, TdfRecoveryResolution> resolutions,
  ) {
    for (final resolution in resolutions.values) {
      if (resolution == TdfRecoveryResolution.recoverAsNew) {
        return true;
      }
    }
    return false;
  }

  /// Checks whether [taskMap] contains any directed dependency cycle.
  static bool _hasDependencyCycle(Map<String, TaskItem> taskMap) {
    final state = <String, int>{};
    for (final id in taskMap.keys) {
      if ((state[id] ?? 0) == 0 && _visitCycleDfs(id, taskMap, state)) {
        return true;
      }
    }
    return false;
  }

  /// Returns whether any label in [labelIds] carries a non-empty `LocationTaskCondition` in [labelsById].
  static bool _hasLiveLabelLocationRule(
    List<String> labelIds,
    Map<String, TdfLabel> labelsById,
  ) {
    for (final labelId in labelIds) {
      final label = labelsById[labelId];
      if (label != null && _countLocationRefs(label.conditions) > 0) {
        return true;
      }
    }
    return false;
  }

  /// Returns whether [record] was already acknowledged in [baseline] when [discard] is true.
  static bool _isAckedLabel(
    TdfDeletedLabelRecord record,
    TdfDeletedBlock? baseline,
    bool discard,
  ) {
    final baselineAt = baseline?.findLabelRecord(record.labelId)?.deletedAt;
    return discard &&
        baselineAt != null &&
        !record.deletedAt.isAfter(baselineAt);
  }

  /// Returns whether [record] was already acknowledged in [baseline] when [discard] is true.
  static bool _isAckedLocation(
    TdfDeletedLocationRecord record,
    TdfDeletedBlock? baseline,
    bool discard,
  ) {
    final baselineAt = baseline
        ?.findLocationRecord(record.locationId)
        ?.deletedAt;
    return discard &&
        baselineAt != null &&
        !record.deletedAt.isAfter(baselineAt);
  }

  /// Returns whether [record] was already acknowledged in [baseline] when [discard] is true.
  static bool _isAckedTask(
    TdfDeletedTaskRecord record,
    TdfDeletedBlock? baseline,
    bool discard,
  ) {
    final baselineAt = baseline?.findTaskRecord(record.taskId)?.deletedAt;
    return discard &&
        baselineAt != null &&
        !record.deletedAt.isAfter(baselineAt);
  }

  /// Returns whether a deletion record with [deletedAt] has expired at [now] when [prune] is true.
  static bool _isDeletedRecordExpired(
    DateTime deletedAt,
    DateTime now,
    bool prune,
  ) =>
      prune &&
      now.difference(deletedAt).inSeconds > TaskBoard.completedRetentionSeconds;

  /// Returns the later of [left] and optional [right].
  static DateTime _laterDate(DateTime left, DateTime? right) =>
      (right != null && right.isAfter(left)) ? right : left;

  /// Remaps [locationIds] via [locationIdMap] while omitting [discardedLocationIds].
  static ({List<String> mappedIds, bool changed}) _mapAndFilterLocationIds(
    List<String> locationIds,
    Map<String, String> locationIdMap,
    Set<String> discardedLocationIds,
  ) {
    final mappedIds = <String>[];
    var changed = false;
    for (final locId in locationIds) {
      if (discardedLocationIds.contains(locId)) {
        changed = true;
        continue;
      }
      final mapped = locationIdMap[locId];
      if (mapped != null) {
        changed = true;
        mappedIds.add(mapped);
      } else {
        mappedIds.add(locId);
      }
    }
    return (mappedIds: mappedIds, changed: changed);
  }

  /// Deduplicates and sorts [labelIds] in ascending ASCII order.
  static List<String> _normalizeMappedLabelIds(Iterable<String> labelIds) {
    final sorted = <String>{...labelIds}.toList()..sort();
    return sorted.isEmpty ? const <String>[] : sorted;
  }

  /// Prepares [staleBoard] for `TDF-REC-002` recovery by rewriting `recoverAsNew` IDs and stripping discarded stale-only references.
  static ({
    TaskBoard board,
    Set<String> freshlyRecoveredLocationIds,
    Set<String> freshlyRecoveredLabelIds,
    Set<String> freshlyRecoveredTaskIds,
    Set<String> rewrittenLabelIds,
    Set<String> rewrittenTaskIds,
    Set<String> discardedTaskIds,
  })
  _prepareBoardForRecovery({
    required TaskBoard staleBoard,
    required TaskBoard advancedBoard,
    required TaskBoard? baseline,
    required Set<String> recoverLocationIds,
    required Set<String> recoverLabelIds,
    required Set<String> recoverTaskIds,
    required bool discardAllUnrecoveredStaleOnly,
    Map<String, TdfRecoveryResolution> explicitTaskResolutions = const {},
    Map<String, TdfRecoveryResolution> explicitLabelResolutions = const {},
    Map<String, TdfRecoveryResolution> explicitLocationResolutions = const {},
    required DateTime now,
    required DateTime? localEvaluationTime,
    required TdfTimeZoneContext? timeZone,
    required Duration? dueLeadWindow,
  }) {
    final usedIds = _collectUsedIdsForRecovery(
      staleBoard,
      advancedBoard,
      baseline,
    );
    final staleLocationIds = <String>{
      for (final location in staleBoard.locations) location.id,
    };
    final staleLabelIds = <String>{
      for (final label in staleBoard.labels) label.id,
    };
    final staleTaskIds = <String>{
      for (final task in staleBoard.allTasks) task.id,
    };
    final advancedLocationIds = <String>{
      for (final location in advancedBoard.locations) location.id,
    };
    final advancedLabelIds = <String>{
      for (final label in advancedBoard.labels) label.id,
    };
    final advancedTaskIds = <String>{
      for (final task in advancedBoard.allTasks) task.id,
    };

    final locationIdMap = <String, String>{};
    for (final oldLocId in recoverLocationIds) {
      if (!staleLocationIds.contains(oldLocId) ||
          advancedLocationIds.contains(oldLocId)) {
        continue;
      }
      final newId = generateLocationId(
        timestamp: now,
        existingIds: usedIds.locations,
      );
      usedIds.locations.add(newId);
      locationIdMap[oldLocId] = newId;
    }
    final labelIdMap = <String, String>{};
    for (final oldLabelId in recoverLabelIds) {
      if (!staleLabelIds.contains(oldLabelId) ||
          advancedLabelIds.contains(oldLabelId)) {
        continue;
      }
      final newId = generateLabelId(
        timestamp: now,
        existingIds: usedIds.labels,
      );
      usedIds.labels.add(newId);
      labelIdMap[oldLabelId] = newId;
    }
    final taskIdMap = <String, String>{};
    for (final oldTaskId in recoverTaskIds) {
      if (!staleTaskIds.contains(oldTaskId) ||
          advancedTaskIds.contains(oldTaskId)) {
        continue;
      }
      final newId = generateTaskId(timestamp: now, existingIds: usedIds.tasks);
      usedIds.tasks.add(newId);
      taskIdMap[oldTaskId] = newId;
    }

    final discardedLocationIds = <String>{
      for (final location in staleBoard.locations)
        if (!locationIdMap.containsKey(location.id) &&
            !advancedLocationIds.contains(location.id) &&
            advancedBoard.deletedBlock.findLocationRecord(location.id) ==
                null &&
            (discardAllUnrecoveredStaleOnly ||
                explicitLocationResolutions[location.id] ==
                    TdfRecoveryResolution.discard))
          location.id,
    };
    final discardedLabelIds = <String>{
      for (final label in staleBoard.labels)
        if (!labelIdMap.containsKey(label.id) &&
            !advancedLabelIds.contains(label.id) &&
            advancedBoard.deletedBlock.findLabelRecord(label.id) == null &&
            (discardAllUnrecoveredStaleOnly ||
                explicitLabelResolutions[label.id] ==
                    TdfRecoveryResolution.discard))
          label.id,
    };
    final discardedTaskIds = <String>{
      for (final task in staleBoard.allTasks)
        if (!taskIdMap.containsKey(task.id) &&
            !advancedTaskIds.contains(task.id) &&
            advancedBoard.deletedBlock.findTaskRecord(task.id) == null &&
            (discardAllUnrecoveredStaleOnly ||
                explicitTaskResolutions[task.id] ==
                    TdfRecoveryResolution.discard))
          task.id,
    };

    final adjustedLocations = <TdfLocation>[
      for (final location in staleBoard.locations)
        if (locationIdMap[location.id] case final newId?)
          location.copyWith(
            id: newId,
            modifiedAt: TaskItem.nextModifiedTimestamp(
              now,
              location.effectiveModifiedAt,
            ),
          )
        else if (!discardedLocationIds.contains(location.id))
          location,
    ];

    final rewrittenLabelIds = <String>{};
    final adjustedLabels = <TdfLabel>[
      for (final label in staleBoard.labels)
        if (labelIdMap[label.id] case final newId?)
          _rewriteAndStripLabel(
            label,
            newId: newId,
            isNewEntity: true,
            locationIdMap: locationIdMap,
            discardedLocationIds: discardedLocationIds,
            now: now,
            rewrittenSharedOut: null,
          )
        else if (!discardedLabelIds.contains(label.id))
          _rewriteAndStripLabel(
            label,
            newId: label.id,
            isNewEntity: false,
            locationIdMap: locationIdMap,
            discardedLocationIds: discardedLocationIds,
            now: now,
            rewrittenSharedOut: rewrittenLabelIds,
          ),
    ];

    final effectiveLabelsById = <String, TdfLabel>{
      for (final label in advancedBoard.labels) label.id: label,
      for (final label in adjustedLabels) label.id: label,
    };
    final scopedBeforeIds = <String>{
      for (final label in staleBoard.labels)
        if (label.isScoped) label.id,
      for (final label in advancedBoard.labels)
        if (label.isScoped) label.id,
      if (baseline != null)
        for (final label in baseline.labels)
          if (label.isScoped) label.id,
    };

    final rewrittenTaskIds = <String>{};
    final evictedQueueIds = <String>{};
    final adjustedTasks = <TaskItem>[
      for (final task in staleBoard.allTasks)
        if (taskIdMap[task.id] case final newId?)
          _rewriteAndStripTask(
            task,
            newId: newId,
            isNewEntity: true,
            labelIdMap: labelIdMap,
            taskIdMap: taskIdMap,
            locationIdMap: locationIdMap,
            discardedLabelIds: discardedLabelIds,
            discardedTaskIds: discardedTaskIds,
            discardedLocationIds: discardedLocationIds,
            effectiveLabelsById: effectiveLabelsById,
            scopedBeforeIds: scopedBeforeIds,
            now: now,
            rewrittenSharedOut: null,
            evictedQueueOut: evictedQueueIds,
          )
        else if (!discardedTaskIds.contains(task.id))
          _rewriteAndStripTask(
            task,
            newId: task.id,
            isNewEntity: false,
            labelIdMap: labelIdMap,
            taskIdMap: taskIdMap,
            locationIdMap: locationIdMap,
            discardedLabelIds: discardedLabelIds,
            discardedTaskIds: discardedTaskIds,
            discardedLocationIds: discardedLocationIds,
            effectiveLabelsById: effectiveLabelsById,
            scopedBeforeIds: scopedBeforeIds,
            now: now,
            rewrittenSharedOut: rewrittenTaskIds,
            evictedQueueOut: evictedQueueIds,
          ),
    ];

    final survivingTaskIdSet = <String>{
      for (final task in adjustedTasks) task.id,
    };
    final adjustedQueueIds = <String>[
      for (final id in staleBoard.queueBlock.taskIds)
        if (taskIdMap[id] case final mapped?
            when !evictedQueueIds.contains(mapped) &&
                survivingTaskIdSet.contains(mapped))
          mapped
        else if (!discardedTaskIds.contains(id) &&
            !evictedQueueIds.contains(id) &&
            survivingTaskIdSet.contains(id))
          id,
    ];

    final preparedBoard = TaskBoard.evaluate(
      tasks: adjustedTasks,
      labels: adjustedLabels,
      locations: adjustedLocations,
      deletedBlock: discardAllUnrecoveredStaleOnly
          ? _filterStaleDeletedBlockForRecovery(
              staleDeleted: staleBoard.deletedBlock,
              advancedBoard: advancedBoard,
              baselineDeleted: baseline?.deletedBlock,
              now: now,
            )
          : staleBoard.deletedBlock,
      queueBlock: staleBoard.queueBlock.copyWith(taskIds: adjustedQueueIds),
      evaluationTime: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
      pruneExpiredCompleted: false,
    );
    return (
      board: preparedBoard,
      freshlyRecoveredLocationIds: locationIdMap.values.toSet(),
      freshlyRecoveredLabelIds: labelIdMap.values.toSet(),
      freshlyRecoveredTaskIds: taskIdMap.values.toSet(),
      rewrittenLabelIds: rewrittenLabelIds,
      rewrittenTaskIds: rewrittenTaskIds,
      discardedTaskIds: discardedTaskIds,
    );
  }

  /// Builds a non-throwing preview of post-cascade [labels] with [tombstonedLocationIds] removed.
  static Map<String, TdfLabel> _previewPostCascadeLabels(
    List<TdfLabel> labels,
    Set<String> tombstonedLocationIds,
  ) {
    return <String, TdfLabel>{
      for (final label in labels)
        label.id: tombstonedLocationIds.isEmpty
            ? label
            : label.copyWith(
                conditions: _stripLocationsFromConditionsPreview(
                  label.conditions,
                  tombstonedLocationIds,
                ),
              ),
    };
  }

  /// Garbage-collects `> 30`-day `Completed` tasks into [deletedBlock] without incrementing `generation` (`TDF-PUB-004` Point 1).
  static ({List<TaskItem> survivingTasks, TdfDeletedBlock deletedBlock})
  _pruneExpiredCompletedTasksIntoDeleted(
    List<TaskItem> tasks,
    TdfDeletedBlock deletedBlock,
    DateTime now,
  ) {
    final surviving = <TaskItem>[];
    final taskRecordsById = <String, TdfDeletedTaskRecord>{
      for (final record in deletedBlock.tasks) record.taskId: record,
    };
    var prunedAny = false;

    for (final task in tasks) {
      final finishedAt = task.completedAt;
      final isExpiredCompleted =
          (task.isCompleted || finishedAt != null) &&
          finishedAt != null &&
          now.difference(finishedAt).inSeconds >
              TaskBoard.completedRetentionSeconds;
      if (!isExpiredCompleted) {
        surviving.add(task);
        continue;
      }
      prunedAny = true;
      final tombstoneAt = TaskItem.nextModifiedTimestamp(
        now,
        task.effectiveModifiedAt,
      );
      final freshRecord = TdfDeletedTaskRecord(
        taskId: task.id,
        deletedAt: tombstoneAt,
        completionsCheckpoint: task.completions,
      );
      final existing = taskRecordsById[task.id];
      taskRecordsById[task.id] =
          existing?.mergeWith(freshRecord) ?? freshRecord;
    }

    if (!prunedAny) {
      return (survivingTasks: tasks, deletedBlock: deletedBlock);
    }
    final totalRecords =
        taskRecordsById.length +
        deletedBlock.labels.length +
        deletedBlock.locations.length;
    if (totalRecords > TdfDeletedBlock.maxDeletedRecords) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged deleted block exceeds MAX_DELETED_RECORDS ($maxTdfDeletedRecords).',
      );
    }
    final updatedDeleted = deletedBlock.copyWith(tasks: taskRecordsById.values);
    return (survivingTasks: surviving, deletedBlock: updatedDeleted);
  }

  /// Combines legacy [recoverIds] with explicit [resolutions] to determine entity IDs selected for `recoverAsNew`.
  static Set<String> _resolveRecoverIdSet(
    Iterable<String> recoverIds,
    Map<String, TdfRecoveryResolution> resolutions,
  ) {
    final result = <String>{
      for (final id in recoverIds)
        if (resolutions[id] != TdfRecoveryResolution.discard) id,
    };
    for (final entry in resolutions.entries) {
      if (entry.value == TdfRecoveryResolution.recoverAsNew) {
        result.add(entry.key);
      }
    }
    return result;
  }

  /// Resolves $\text{isScoped}(l)$ from merged live labels first, then from [primary], [secondary], and [baseline] for deleted labels (`TDF-MERGE-011`).
  static Set<String> _resolveScopedLabelIds({
    required Map<String, TdfLabel> postCascadeLabelsById,
    required TaskBoard primary,
    required TaskBoard secondary,
    required TaskBoard? baseline,
  }) {
    final result = <String>{
      for (final label in postCascadeLabelsById.values)
        if (label.isScoped) label.id,
      for (final label in primary.labels)
        if (!postCascadeLabelsById.containsKey(label.id) && label.isScoped)
          label.id,
      for (final label in secondary.labels)
        if (!postCascadeLabelsById.containsKey(label.id) && label.isScoped)
          label.id,
      if (baseline != null)
        for (final label in baseline.labels)
          if (!postCascadeLabelsById.containsKey(label.id) && label.isScoped)
            label.id,
    };
    return result;
  }

  /// Resolves undeleted open task IDs that were listed in the surviving live side's `queue` block (`TDF-DEL-003`).
  static Set<String> _resolveUndeletedQueuedTaskIds(
    TaskBoard primary,
    TaskBoard secondary,
    Set<String> undeletedTaskIds,
    Set<String> evictedFromQueueIds,
  ) {
    if (undeletedTaskIds.isEmpty) {
      return const <String>{};
    }
    final primaryQueued = primary.queueBlock.taskIds.toSet();
    final secondaryQueued = secondary.queueBlock.taskIds.toSet();
    final result = <String>{};
    for (final id in undeletedTaskIds) {
      if (evictedFromQueueIds.contains(id)) {
        continue;
      }
      final inSurvivingQueue = primary.findTask(id) != null
          ? primaryQueued.contains(id)
          : secondaryQueued.contains(id);
      if (inSurvivingQueue) {
        result.add(id);
      }
    }
    return result;
  }

  /// Rewrites `condition location` references via [locationIdMap] and strips [discardedLocationIds] on [label] during recovery (`TDF-REC-002`).
  static TdfLabel _rewriteAndStripLabel(
    TdfLabel label, {
    required String newId,
    required bool isNewEntity,
    required Map<String, String> locationIdMap,
    required Set<String> discardedLocationIds,
    required DateTime now,
    required Set<String>? rewrittenSharedOut,
  }) {
    final updatedConditions = <TaskCondition>[];
    var conditionsChanged = false;
    for (final rule in label.conditions) {
      if (rule is! LocationTaskCondition || rule.locationIds.isEmpty) {
        updatedConditions.add(rule);
        continue;
      }
      final mapped = _mapAndFilterLocationIds(
        rule.locationIds,
        locationIdMap,
        discardedLocationIds,
      );
      if (mapped.changed) {
        conditionsChanged = true;
      }
      if (mapped.mappedIds.isNotEmpty) {
        updatedConditions.add(LocationTaskCondition.fromIds(mapped.mappedIds));
      }
    }

    if (!isNewEntity && !conditionsChanged) {
      return label;
    }
    if (!isNewEntity) {
      rewrittenSharedOut?.add(newId);
      return label.copyWith(conditions: updatedConditions);
    }
    return label.copyWith(
      id: newId,
      modifiedAt: TaskItem.nextModifiedTimestamp(
        now,
        label.effectiveModifiedAt,
      ),
      conditions: conditionsChanged ? updatedConditions : label.conditions,
    );
  }

  /// Rewrites recovered IDs and strips discarded label, task, and location references on [task] during recovery (`TDF-REC-002`).
  static TaskItem _rewriteAndStripTask(
    TaskItem task, {
    required String newId,
    required bool isNewEntity,
    required Map<String, String> labelIdMap,
    required Map<String, String> taskIdMap,
    required Map<String, String> locationIdMap,
    required Set<String> discardedLabelIds,
    required Set<String> discardedTaskIds,
    required Set<String> discardedLocationIds,
    required Map<String, TdfLabel> effectiveLabelsById,
    required Set<String> scopedBeforeIds,
    required DateTime now,
    required Set<String>? rewrittenSharedOut,
    required Set<String>? evictedQueueOut,
  }) {
    final isOpen = !task.isCompleted && task.completedAt == null;
    var labelsChanged = false;
    var strippedDiscardedLabel = false;
    final allBeforeWereScoped =
        task.labelIds.isNotEmpty &&
        task.labelIds.every(scopedBeforeIds.contains);
    final rawMappedLabels = <String>[];
    for (final labelId in task.labelIds) {
      if (discardedLabelIds.contains(labelId)) {
        labelsChanged = true;
        strippedDiscardedLabel = true;
        continue;
      }
      final mapped = labelIdMap[labelId];
      if (mapped != null) {
        labelsChanged = true;
        rawMappedLabels.add(mapped);
      } else {
        rawMappedLabels.add(labelId);
      }
    }
    final nextLabels = labelsChanged
        ? _normalizeMappedLabelIds(rawMappedLabels)
        : task.labelIds;
    final lostLastScoped =
        isOpen &&
        strippedDiscardedLabel &&
        allBeforeWereScoped &&
        nextLabels.isEmpty;
    if (lostLastScoped) {
      evictedQueueOut?.add(newId);
    }
    final nextPriority = lostLastScoped ? false : task.isPriority;

    var depsChanged = false;
    final rawMappedDeps = <TdfTaskDependency>[];
    for (final dependency in task.dependencies) {
      if (isOpen && discardedTaskIds.contains(dependency.taskId)) {
        depsChanged = true;
        continue;
      }
      final mappedTarget = taskIdMap[dependency.taskId];
      if (mappedTarget != null) {
        depsChanged = true;
        rawMappedDeps.add(
          TdfTaskDependency(
            taskId: mappedTarget,
            requiredCompletion: dependency.requiredCompletion,
          ),
        );
      } else {
        rawMappedDeps.add(dependency);
      }
    }
    final nextDeps = depsChanged
        ? TdfTaskDependency.normalizeList(rawMappedDeps)
        : task.dependencies;

    final condResult = _rewriteTaskConditionsForRecovery(
      task.conditions,
      nextLabels: nextLabels,
      locationIdMap: locationIdMap,
      discardedLocationIds: discardedLocationIds,
      effectiveLabelsById: effectiveLabelsById,
    );

    final anyPayloadChange =
        labelsChanged ||
        depsChanged ||
        condResult.changed ||
        nextPriority != task.isPriority;
    if (!isNewEntity && !anyPayloadChange) {
      return task;
    }
    if (!isNewEntity) {
      rewrittenSharedOut?.add(newId);
    }
    return task.copyWith(
      id: newId,
      isPriority: nextPriority,
      modifiedAt: isNewEntity
          ? TaskItem.nextModifiedTimestamp(now, task.effectiveModifiedAt)
          : task.modifiedAt,
      labelIds: nextLabels,
      conditions: condResult.changed ? condResult.conditions : task.conditions,
      dependencies: nextDeps,
      blockedByTaskIds: <String>[
        for (final dependency in nextDeps) dependency.taskId,
      ],
    );
  }

  /// Rewrites `condition location` references via [locationIdMap] and strips [discardedLocationIds] on task [conditions] (`TDF-REC-002`).
  static ({List<TaskCondition> conditions, bool changed})
  _rewriteTaskConditionsForRecovery(
    List<TaskCondition> conditions, {
    required List<String> nextLabels,
    required Map<String, String> locationIdMap,
    required Set<String> discardedLocationIds,
    required Map<String, TdfLabel> effectiveLabelsById,
  }) {
    if (conditions.isEmpty ||
        (locationIdMap.isEmpty && discardedLocationIds.isEmpty)) {
      return (conditions: conditions, changed: false);
    }
    final updated = <TaskCondition>[];
    var changed = false;
    for (final rule in conditions) {
      if (rule is! LocationTaskCondition || rule.locationIds.isEmpty) {
        updated.add(rule);
        continue;
      }
      final mapped = _mapAndFilterLocationIds(
        rule.locationIds,
        locationIdMap,
        discardedLocationIds,
      );
      if (mapped.changed) {
        changed = true;
      }
      if (mapped.mappedIds.isNotEmpty) {
        updated.add(LocationTaskCondition.fromIds(mapped.mappedIds));
      } else if (_hasLiveLabelLocationRule(nextLabels, effectiveLabelsById)) {
        updated.add(
          const GroupResetTaskCondition(targetGroup: ConditionGroup.location),
        );
      }
    }
    return (conditions: updated, changed: changed);
  }

  /// Strips [expiredTaskIds] from a single [task]'s `dependencies` (including `Completed` tasks) and advances `modifiedAt` if changed (`TDF-PUB-004`).
  static TaskItem _stripExpiredDepsFromSingleTask(
    TaskItem task,
    Set<String> expiredTaskIds,
    DateTime now, {
    Set<String>? strippedTaskIdsOut,
  }) {
    if (task.dependencies.isEmpty) {
      return task;
    }
    final retained = <TdfTaskDependency>[
      for (final dependency in task.dependencies)
        if (!expiredTaskIds.contains(dependency.taskId)) dependency,
    ];
    if (retained.length == task.dependencies.length) {
      return task;
    }
    strippedTaskIdsOut?.add(task.id);
    return task.copyWith(
      dependencies: retained,
      blockedByTaskIds: <String>[
        for (final dependency in retained) dependency.taskId,
      ],
      modifiedAt: TaskItem.nextModifiedTimestamp(now, task.effectiveModifiedAt),
    );
  }

  /// Strips `blocked` references targeting task deletion records that expired during [afterPrune] (`TDF-PUB-004` Point 2).
  static List<TaskItem> _stripExpiredTaskDependencies(
    List<TaskItem> tasks,
    Map<String, TdfDeletedTaskRecord> beforePrune,
    TdfDeletedBlock afterPrune,
    DateTime now, {
    Set<String>? strippedTaskIdsOut,
  }) {
    if (afterPrune.tasks.length == beforePrune.length) {
      return tasks;
    }
    final retainedDeletedTaskIds = <String>{
      for (final record in afterPrune.tasks) record.taskId,
    };
    final expiredTaskIds = <String>{
      for (final id in beforePrune.keys)
        if (!retainedDeletedTaskIds.contains(id)) id,
    };
    if (expiredTaskIds.isEmpty) {
      return tasks;
    }
    return <TaskItem>[
      for (final task in tasks)
        _stripExpiredDepsFromSingleTask(
          task,
          expiredTaskIds,
          now,
          strippedTaskIdsOut: strippedTaskIdsOut,
        ),
    ];
  }

  /// Removes [tombstonedLocationIds] from [conditions] for the pre-merge label location preview.
  static List<TaskCondition> _stripLocationsFromConditionsPreview(
    List<TaskCondition> conditions,
    Set<String> tombstonedLocationIds,
  ) {
    final result = <TaskCondition>[];
    for (final rule in conditions) {
      if (rule is LocationTaskCondition && rule.locationIds.isNotEmpty) {
        final retained = <String>[
          for (final id in rule.locationIds)
            if (!tombstonedLocationIds.contains(id)) id,
        ];
        if (retained.isNotEmpty) {
          result.add(LocationTaskCondition(locationIds: retained));
        }
      } else {
        result.add(rule);
      }
    }
    return result;
  }

  /// Strips [targetTaskIds] from a single **open** [task]'s `dependencies` (`TDF-REC-002` / `TDF-DEL-003`).
  static TaskItem _stripOpenDepsFromSingleTask(
    TaskItem task,
    Set<String> targetTaskIds,
    DateTime now, {
    Set<String>? strippedTaskIdsOut,
  }) {
    if (task.isCompleted ||
        task.completedAt != null ||
        task.dependencies.isEmpty) {
      return task;
    }
    final retained = <TdfTaskDependency>[
      for (final dependency in task.dependencies)
        if (!targetTaskIds.contains(dependency.taskId)) dependency,
    ];
    if (retained.length == task.dependencies.length) {
      return task;
    }
    strippedTaskIdsOut?.add(task.id);
    return task.copyWith(
      dependencies: retained,
      blockedByTaskIds: <String>[
        for (final dependency in retained) dependency.taskId,
      ],
      modifiedAt: TaskItem.nextModifiedTimestamp(now, task.effectiveModifiedAt),
    );
  }

  /// Strips `blocked` references targeting [targetTaskIds] across all surviving live **open** tasks (`TDF-REC-002` / `TDF-DEL-003`).
  static List<TaskItem> _stripOpenTaskDependenciesForIds(
    List<TaskItem> tasks,
    Set<String> targetTaskIds,
    DateTime now, {
    Set<String>? strippedTaskIdsOut,
  }) {
    if (targetTaskIds.isEmpty || tasks.isEmpty) {
      return tasks;
    }
    return <TaskItem>[
      for (final task in tasks)
        _stripOpenDepsFromSingleTask(
          task,
          targetTaskIds,
          now,
          strippedTaskIdsOut: strippedTaskIdsOut,
        ),
    ];
  }

  /// Throws a [TdfException] at line 1 with [kind] and [message].
  static Never _throwTdf(TdfErrorKind kind, String message) =>
      throw TdfException(kind: kind, line: 1, message: message);

  /// Validates `TDF-VAL-002` `links`, location reference, condition rule, and statement count bounds on [label].
  static void _validateLabelBounds(TdfLabel label) {
    if (label.links.length > maxTdfLinksPerLabel) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged label "${label.id}" exceeds MAX_LINKS_PER_LABEL ($maxTdfLinksPerLabel).',
      );
    }
    if (_countLocationRefs(label.conditions) > maxTdfLocationRefsPerEntity) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged label "${label.id}" exceeds MAX_LOCATION_REFS_PER_ENTITY ($maxTdfLocationRefsPerEntity).',
      );
    }
    final condCounts = _computeConditionRuleAndBlockCounts(label.conditions);
    if (condCounts.ruleStatements > maxTdfConditionRulesPerEntity) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged label "${label.id}" exceeds MAX_CONDITION_RULES_PER_ENTITY ($maxTdfConditionRulesPerEntity).',
      );
    }
    if (label.canonicalDirectChildStatementCount > maxTdfStmtsPerBlock) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged label "${label.id}" exceeds MAX_STMTS_PER_BLOCK ($maxTdfStmtsPerBlock).',
      );
    }
  }

  /// Validates `TDF-VAL-002` statement count bounds on [location].
  static void _validateLocationBounds(TdfLocation location) {
    if (location.canonicalDirectChildStatementCount > maxTdfStmtsPerBlock) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged location "${location.id}" exceeds MAX_STMTS_PER_BLOCK ($maxTdfStmtsPerBlock).',
      );
    }
  }

  /// Validates `TDF-VAL-002` directive argument, link, history, condition rule, and statement count bounds on [task].
  static void _validateTaskBounds(TaskItem task) {
    if (task.labelIds.length > maxTdfArgsPerStmt) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged task "${task.id}" exceeds MAX_ARGS_PER_STMT ($maxTdfArgsPerStmt) on labels.',
      );
    }
    if (task.dependencies.length > maxTdfArgsPerStmt) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged task "${task.id}" exceeds MAX_ARGS_PER_STMT ($maxTdfArgsPerStmt) on blocked.',
      );
    }
    if (_countLocationRefs(task.conditions) > maxTdfLocationRefsPerEntity) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged task "${task.id}" exceeds MAX_LOCATION_REFS_PER_ENTITY ($maxTdfLocationRefsPerEntity).',
      );
    }
    final condCounts = _computeConditionRuleAndBlockCounts(task.conditions);
    if (condCounts.ruleStatements > maxTdfConditionRulesPerEntity) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged task "${task.id}" exceeds MAX_CONDITION_RULES_PER_ENTITY ($maxTdfConditionRulesPerEntity).',
      );
    }
    if (task.links.length > maxTdfLinksPerTask) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged task "${task.id}" exceeds MAX_LINKS_PER_TASK ($maxTdfLinksPerTask).',
      );
    }
    if (task.history.length > maxTdfHistoryPerTask) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged task "${task.id}" exceeds MAX_HISTORY_PER_TASK ($maxTdfHistoryPerTask).',
      );
    }
    if (task.subtasks.length > maxTdfStmtsPerBlock ||
        task.canonicalDirectChildStatementCount > maxTdfStmtsPerBlock) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged task "${task.id}" exceeds MAX_STMTS_PER_BLOCK ($maxTdfStmtsPerBlock).',
      );
    }
  }

  /// Recursive DFS helper for cycle detection (`0` = unvisited, `1` = visiting, `2` = visited).
  static bool _visitCycleDfs(
    String currentId,
    Map<String, TaskItem> taskMap,
    Map<String, int> state,
  ) {
    state[currentId] = 1;
    final dependencies =
        taskMap[currentId]?.dependencies ?? const <TdfTaskDependency>[];
    for (final dependency in dependencies) {
      final targetId = dependency.taskId;
      if (targetId == currentId) {
        return true;
      }
      if (!taskMap.containsKey(targetId)) {
        continue;
      }
      final targetState = state[targetId] ?? 0;
      if (targetState == 1 ||
          (targetState == 0 && _visitCycleDfs(targetId, taskMap, state))) {
        return true;
      }
    }
    state[currentId] = 2;
    return false;
  }
}
