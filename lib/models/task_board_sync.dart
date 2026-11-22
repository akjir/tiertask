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
import 'task_board_recovery.dart';
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
        if (!TaskBoardRecovery.isAckedTask(record, baseline, discardPrimary))
          record.taskId: record,
    };
    for (final record in secondary.tasks) {
      if (!TaskBoardRecovery.isAckedTask(record, baseline, discardSecondary)) {
        final previous = taskRecords[record.taskId];
        taskRecords[record.taskId] = previous?.mergeWith(record) ?? record;
      }
    }

    final labelRecords = <String, TdfDeletedLabelRecord>{
      for (final record in primary.labels)
        if (!TaskBoardRecovery.isAckedLabel(record, baseline, discardPrimary))
          record.labelId: record,
    };
    for (final record in secondary.labels) {
      if (!TaskBoardRecovery.isAckedLabel(record, baseline, discardSecondary)) {
        final previous = labelRecords[record.labelId];
        if (previous == null || record.deletedAt.isAfter(previous.deletedAt)) {
          labelRecords[record.labelId] = record;
        }
      }
    }

    final locationRecords = <String, TdfDeletedLocationRecord>{
      for (final record in primary.locations)
        if (!TaskBoardRecovery.isAckedLocation(
          record,
          baseline,
          discardPrimary,
        ))
          record.locationId: record,
    };
    for (final record in secondary.locations) {
      if (!TaskBoardRecovery.isAckedLocation(
        record,
        baseline,
        discardSecondary,
      )) {
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
        if (!TaskBoardRecovery.isDeletedRecordExpired(
          record.deletedAt,
          now,
          pruneExpired,
        ))
          record,
    ];
    final activeLabels = <TdfDeletedLabelRecord>[
      for (final record in deletedLabels.values)
        if (!TaskBoardRecovery.isDeletedRecordExpired(
          record.deletedAt,
          now,
          pruneExpired,
        ))
          record,
    ];
    final activeLocations = <TdfDeletedLocationRecord>[
      for (final record in deletedLocations.values)
        if (!TaskBoardRecovery.isDeletedRecordExpired(
          record.deletedAt,
          now,
          pruneExpired,
        ))
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
    final rawIndices = SyncBoardIndices.fromBoards(
      primary,
      secondary,
      baseline,
    );

    TaskBoardReconciler.verifyGenerationsAndCompletionHistory(
      rawBoards,
      ackGen,
      indices: rawIndices,
    );
    final refreshFlags = TaskBoardReconciler.resolveGenerationRefreshFlags(
      rawBoards,
      ackGen,
      requireAcknowledgedGeneration,
    );
    final inlineRewrite = TaskBoardRecovery.applyInlineRecoveryRewrite(
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
    final indices =
        (identical(effectivePrimary, primary) &&
            identical(effectiveSecondary, secondary))
        ? rawIndices
        : SyncBoardIndices.fromBoards(
            effectivePrimary,
            effectiveSecondary,
            baseline,
          );
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
          indices: indices,
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
          indices: indices,
        );
    final newlyRefLocations =
        TaskBoardReconciler.computeNewlyReferencedLocationIds(
          boards,
          initialDeleted.tasks,
          initialDeleted.labels,
          explicitlyDeletedTaskIds: explicitlyDeletedTaskIds,
          explicitlyDeletedLabelIds: explicitlyDeletedLabelIds,
          indices: indices,
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
      indices: indices,
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
      indices: indices,
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
      indices: indices,
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
      indices: indices,
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
          indices: indices,
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
          indices: indices,
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
      reconciledLiveTasks: taskOutcome.liveTasks,
      liveTasksAfterCascades: tasksAfterLocStrip,
      uncleanedLiveTasksById: taskOutcome.uncleanedLiveTasksById,
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
      indices: indices,
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
      indices: indices,
      now: now,
      cleanupMode: cleanupMode,
    );

    final undeletedQueuedTaskIds = _resolveUndeletedQueuedTaskIds(
      effectivePrimary,
      effectiveSecondary,
      taskOutcome.undeletedTaskIds,
      evictedFromQueueIds,
      indices.primaryTasks,
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
    final prepared = TaskBoardRecovery.prepareBoardForRecovery(
      staleBoard: localBoard,
      advancedBoard: sharedBoard,
      baseline: baseline,
      recoverLocationIds: TaskBoardRecovery.resolveRecoverIdSet(
        locationRecoveryResolutions,
      ),
      recoverLabelIds: TaskBoardRecovery.resolveRecoverIdSet(
        labelRecoveryResolutions,
      ),
      recoverTaskIds: TaskBoardRecovery.resolveRecoverIdSet(
        taskRecoveryResolutions,
      ),
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
    final totalBlocks = TaskBoardEvaluator.computeCanonicalBlockCount(
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
    if (TaskBoardEvaluator.hasDependencyCycle(taskMap)) {
      _throwTdf(
        TdfErrorKind.circularDependency,
        'Merged document contains a circular task dependency.',
      );
    }
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

  /// Applies `TDF-MERGE-011` label and location deletion cascades to uncleaned candidates differing from their reconciled live counterpart.
  static Map<String, TaskItem> _applyCascadesToUncleanedTasks({
    required List<TaskItem> reconciledLiveTasks,
    required List<TaskItem> liveTasksAfterCascades,
    required Map<String, TaskItem> uncleanedLiveTasksById,
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
    required SyncBoardIndices indices,
  }) {
    if (uncleanedLiveTasksById.isEmpty) {
      return const <String, TaskItem>{};
    }
    final result = <String, TaskItem>{};
    final distinctUncleaned = <TaskItem>[];
    for (var i = 0; i < reconciledLiveTasks.length; i++) {
      final liveTask = reconciledLiveTasks[i];
      final uncleaned = uncleanedLiveTasksById[liveTask.id];
      if (uncleaned == null) {
        continue;
      }
      if (identical(uncleaned, liveTask)) {
        result[liveTask.id] = liveTasksAfterCascades[i];
      } else {
        distinctUncleaned.add(uncleaned);
      }
    }
    if (distinctUncleaned.isEmpty) {
      return result;
    }
    final afterLabels =
        TaskBoardReconciler.stripDeletedLabelsAndValidateReferences(
          distinctUncleaned,
          validLabelIds,
          deletedLabelsById,
          baselineLabels,
          discardedLabelIds: discardedLabelIds,
          explicitlyDeletedLabelIds: explicitlyDeletedLabelIds,
          knownScopedLabelIds: knownScopedLabelIds,
          boards: boards,
          now: now,
          indices: indices,
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
    for (final task in afterLocations) {
      result[task.id] = task;
    }
    return result;
  }

  /// Assigns deterministic `TDF-MERGE-004` revisions across [tasksAfterCleanup].
  static List<TaskItem> _assignFinalMergedTaskRevisions({
    required List<TaskItem> tasksAfterCleanup,
    required List<TaskItem> reconciledLiveTasks,
    required Map<String, TaskItem> uncleanedAfterCascadesById,
    required Set<String> undeletedTaskIds,
    required Set<String> freshlyRecoveredTaskIds,
    required Set<String> mutatedByNowTaskIds,
    required SyncBoardIndices indices,
    required DateTime now,
    required TdfCleanupMode cleanupMode,
  }) {
    final primaryById = indices.primaryTasks;
    final secondaryById = indices.secondaryTasks;
    final baselineById = indices.baselineTasks;
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
          baselineTask: baselineById?[task.id],
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
      final targetTimestamp = (mutatedByNowStrip && now.isAfter(baseDecision))
          ? _checkedTimestamp(now)
          : _checkedTimestamp(baseDecision);
      return _withModifiedAt(finalTask, targetTimestamp);
    }

    if (primaryTask != null && secondaryTask != null) {
      if (!mutatedByNowStrip &&
          identical(finalTask, primaryTask) &&
          primaryTask == secondaryTask &&
          (baselineTask == null || primaryTask == baselineTask)) {
        return finalTask;
      }
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
        return _withModifiedAt(finalTask, _checkedTimestamp(withNowStrip));
      }

      if (referenceExisting.completions == finalTask.completions &&
          TdfPayloadComparison.compareTaskPayloads(
                referenceExisting,
                finalTask,
              ) ==
              0) {
        return _withModifiedAt(finalTask, referenceExisting.modifiedAt);
      }

      final bumped = _checkedBumpPlusOneSecond(maxObserved);
      if (cleanupMode == TdfCleanupMode.deferred ||
          (uncleanedTask != null &&
              TdfPayloadComparison.compareTaskPayloads(
                    finalTask,
                    uncleanedTask,
                  ) ==
                  0)) {
        return _withModifiedAt(finalTask, bumped);
      }
      final withNow = now.isAfter(bumped) ? now : bumped;
      return _withModifiedAt(finalTask, _checkedTimestamp(withNow));
    }

    final sourceTask = primaryTask ?? secondaryTask;
    if (sourceTask == null) {
      return finalTask;
    }
    if (wasFreshlyRecovered) {
      return _withModifiedAt(
        finalTask,
        _checkedTimestamp(sourceTask.effectiveModifiedAt),
      );
    }
    if (mutatedByNowStrip) {
      final bumpedStrip = _checkedBumpPlusOneSecond(
        sourceTask.effectiveModifiedAt,
      );
      final withNowStrip = now.isAfter(bumpedStrip) ? now : bumpedStrip;
      return _withModifiedAt(finalTask, _checkedTimestamp(withNowStrip));
    }
    if (sourceTask.completions == finalTask.completions &&
        TdfPayloadComparison.compareTaskPayloads(sourceTask, finalTask) == 0) {
      return _withModifiedAt(finalTask, sourceTask.modifiedAt);
    }
    final bumped = _checkedBumpPlusOneSecond(sourceTask.effectiveModifiedAt);
    if (cleanupMode == TdfCleanupMode.deferred ||
        (uncleanedTask != null &&
            TdfPayloadComparison.compareTaskPayloads(
                  finalTask,
                  uncleanedTask,
                ) ==
                0)) {
      return _withModifiedAt(finalTask, bumped);
    }
    final withNow = now.isAfter(bumped) ? now : bumped;
    return _withModifiedAt(finalTask, _checkedTimestamp(withNow));
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

  /// Orders concurrent queue additions by ascending UTC `createdAt`, then ascending ASCII `id` (`TDF-QSYNC-001`).
  static int _compareConcurrentQueuedTasks(TaskItem left, TaskItem right) {
    final createdCmp = left.createdAt.compareTo(right.createdAt);
    return createdCmp != 0 ? createdCmp : left.id.compareTo(right.id);
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

  /// Returns the later of [left] and optional [right].
  static DateTime _laterDate(DateTime left, DateTime? right) =>
      (right != null && right.isAfter(left)) ? right : left;

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
    Map<String, TaskItem> primaryTasksById,
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
      final inSurvivingQueue = primaryTasksById.containsKey(id)
          ? primaryQueued.contains(id)
          : secondaryQueued.contains(id);
      if (inSurvivingQueue) {
        result.add(id);
      }
    }
    return result;
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
    if (TdfMetadata.countLocationRefs(label.conditions) >
        maxTdfLocationRefsPerEntity) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged label "${label.id}" exceeds MAX_LOCATION_REFS_PER_ENTITY ($maxTdfLocationRefsPerEntity).',
      );
    }
    final condCounts = TaskBoardEvaluator.computeConditionRuleAndBlockCounts(
      label.conditions,
    );
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
    if (TdfMetadata.countLocationRefs(task.conditions) >
        maxTdfLocationRefsPerEntity) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged task "${task.id}" exceeds MAX_LOCATION_REFS_PER_ENTITY ($maxTdfLocationRefsPerEntity).',
      );
    }
    final condCounts = TaskBoardEvaluator.computeConditionRuleAndBlockCounts(
      task.conditions,
    );
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

  /// Returns [task] directly when its `modifiedAt` already equals [targetModifiedAt], avoiding redundant copies.
  static TaskItem _withModifiedAt(TaskItem task, DateTime? targetModifiedAt) {
    if (task.modifiedAt == targetModifiedAt) {
      return task;
    }
    return task.copyWith(
      modifiedAt: targetModifiedAt,
      clearModifiedAt: targetModifiedAt == null,
    );
  }
}
