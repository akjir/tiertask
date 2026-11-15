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
/// reconciliation, and shared queue merge engine for [TaskBoard] documents
/// per `TDF_SPEC_0.7.0.md` Sections 6.7, 6.8, 6.9.5, and 6.11.2.
@immutable
class TaskBoardSync {
  /// Prevents instantiation of this stateless helper class.
  const TaskBoardSync._();

  /// Combines active deletion records from [primary] and [secondary], discarding old acknowledged records when one side advanced generation.
  static ({
    Map<String, TdfDeletedTaskRecord> tasks,
    Map<String, TdfDeletedLabelRecord> labels,
    Map<String, TdfDeletedLocationRecord> locations,
  })
  combineInitialDeletedRecords(
    TdfDeletedBlock primary,
    TdfDeletedBlock secondary,
    TdfDeletedBlock? baseline,
    Map<String, DateTime> deletedLabelTimestamps, [
    Map<String, DateTime> deletedLocationTimestamps = const {},
  ]) {
    final discardPrimary = primary.generation < secondary.generation;
    final discardSecondary = secondary.generation < primary.generation;

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
    final extraLabels = <TdfDeletedLabelRecord>[
      for (final record in secondary.labels)
        if (!_isAckedLabel(record, baseline, discardSecondary)) record,
      for (final entry in deletedLabelTimestamps.entries)
        if (isValidLabelId(entry.key))
          TdfDeletedLabelRecord(
            labelId: entry.key,
            deletedAt: TaskItem.normalizeTimestamp(entry.value),
          ),
    ];
    for (final record in extraLabels) {
      final previous = labelRecords[record.labelId];
      if (previous == null || record.deletedAt.isAfter(previous.deletedAt)) {
        labelRecords[record.labelId] = record;
      }
    }

    final locationRecords = <String, TdfDeletedLocationRecord>{
      for (final record in primary.locations)
        if (!_isAckedLocation(record, baseline, discardPrimary))
          record.locationId: record,
    };
    final extraLocations = <TdfDeletedLocationRecord>[
      for (final record in secondary.locations)
        if (!_isAckedLocation(record, baseline, discardSecondary)) record,
      for (final entry in deletedLocationTimestamps.entries)
        if (isValidLocationId(entry.key))
          TdfDeletedLocationRecord(
            locationId: entry.key,
            deletedAt: TaskItem.normalizeTimestamp(entry.value),
          ),
    ];
    for (final record in extraLocations) {
      final previous = locationRecords[record.locationId];
      if (previous == null || record.deletedAt.isAfter(previous.deletedAt)) {
        locationRecords[record.locationId] = record;
      }
    }

    return (
      tasks: taskRecords,
      labels: labelRecords,
      locations: locationRecords,
    );
  }

  /// Prunes expired deletion records (> `2,592,000` seconds) and increments `generation` once when records are retired per Section 6.8.3.
  static TdfDeletedBlock finalizeDeletedBlock(
    int baseGeneration,
    Map<String, TdfDeletedTaskRecord> deletedTasks,
    Map<String, TdfDeletedLabelRecord> deletedLabels,
    bool retiredByUndelete,
    bool pruneExpired,
    DateTime now, [
    Map<String, TdfDeletedLocationRecord> deletedLocations = const {},
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
        'Merged deleted block exceeds MAX_DELETED_RECORDS (2000).',
      );
    }

    final anyExpired =
        activeTasks.length != deletedTasks.length ||
        activeLabels.length != deletedLabels.length ||
        activeLocations.length != deletedLocations.length;
    var nextGeneration = baseGeneration;
    if (anyExpired || retiredByUndelete) {
      if (baseGeneration >= TdfDeletedBlock.maxGeneration) {
        _throwTdf(
          TdfErrorKind.limitExceeded,
          'Deletion history generation exceeds MAX_SYNC_GENERATION (9007199254740991).',
        );
      }
      nextGeneration = baseGeneration + 1;
    }
    return TdfDeletedBlock(
      generation: nextGeneration,
      tasks: activeTasks,
      labels: activeLabels,
      locations: activeLocations,
    );
  }

  /// Merges [primary] and [secondary] entity-by-entity (`location`, `label`, `task`,
  /// `deleted`, and `queue` blocks) using [baseline], [acknowledgedGeneration],
  /// [deletedLabelTimestamps], [deletedLocationTimestamps], [taskConflictResolutions],
  /// [labelConflictResolutions], and [locationConflictResolutions], and evaluates the
  /// 6-tier pipeline at [evaluationTime].
  static TaskBoard merge({
    required TaskBoard primary,
    required TaskBoard secondary,
    TaskBoard? baseline,
    int? acknowledgedGeneration,
    Map<String, DateTime> deletedLabelTimestamps = const {},
    Map<String, DateTime> deletedLocationTimestamps = const {},
    Map<String, TdfDeletionResolution> taskConflictResolutions = const {},
    Map<String, TdfDeletionResolution> labelConflictResolutions = const {},
    Map<String, TdfDeletionResolution> locationConflictResolutions = const {},
    required DateTime evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
    bool pruneExpiredDeleted = true,
    bool requireAcknowledgedGeneration = false,
    bool applyPostMergeBlockCleanup = true,
    TdfSchemaVersion schemaVersion = TdfSchemaVersion.v070,
  }) {
    final now = TaskItem.normalizeTimestamp(evaluationTime);
    final ackGen = acknowledgedGeneration ?? baseline?.deletedBlock.generation;
    final leftGen = primary.deletedBlock.generation;
    final rightGen = secondary.deletedBlock.generation;
    final boards = (primary, secondary, baseline);
    final options = (ackGen, requireAcknowledgedGeneration, now);

    TaskBoardReconciler.verifyGenerationsAndCompletionHistory(boards, ackGen);
    final initialDeleted = combineInitialDeletedRecords(
      primary.deletedBlock,
      secondary.deletedBlock,
      baseline?.deletedBlock,
      deletedLabelTimestamps,
      deletedLocationTimestamps,
    );
    final newlyRefLocations =
        TaskBoardReconciler.computeNewlyReferencedLocationIds(
          boards,
          initialDeleted.tasks,
          initialDeleted.labels,
        );
    final locationOutcome = TaskBoardReconciler.reconcileLocations(
      boards,
      initialDeleted.locations,
      locationConflictResolutions,
      options,
      newlyReferencedLocationIds: newlyRefLocations,
    );
    final validLocationIds = <String>{
      for (final location in locationOutcome.liveLocations) location.id,
    };
    final tombstonedLocationIds = <String>{
      ...locationOutcome.deletedLocationsById.keys,
      if (baseline != null)
        for (final location in baseline.locations)
          if (!validLocationIds.contains(location.id)) location.id,
    };

    final newlyRefLabels = TaskBoardReconciler.computeNewlyReferencedLabelIds(
      boards,
      initialDeleted.tasks,
    );
    final labelOutcome = TaskBoardReconciler.reconcileLabels(
      boards,
      initialDeleted.labels,
      labelConflictResolutions,
      options,
      tombstonedLocationIds: tombstonedLocationIds,
      newlyReferencedLabelIds: newlyRefLabels,
    );
    final validLabelIds = <String>{
      for (final label in labelOutcome.liveLabels) label.id,
    };
    final tombstonedLabelIds = <String>{
      ...labelOutcome.deletedLabelsById.keys,
      if (baseline != null)
        for (final label in baseline.labels)
          if (!validLabelIds.contains(label.id)) label.id,
    };
    final previewLabelsById = _previewPostCascadeLabels(
      labelOutcome.liveLabels,
      tombstonedLocationIds,
    );

    final taskOutcome = TaskBoardReconciler.reconcileTasks(
      boards,
      initialDeleted.tasks,
      taskConflictResolutions,
      options,
      tombstonedLocationIds: tombstonedLocationIds,
      tombstonedLabelIds: tombstonedLabelIds,
      validLabelIds: validLabelIds,
      postCascadeLabelsById: previewLabelsById,
      schemaVersion: schemaVersion,
      applyPostMergeBlockCleanup: applyPostMergeBlockCleanup,
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
        );
    final postCascadeLabelsById = <String, TdfLabel>{
      for (final label in labelsAfterStrip) label.id: label,
    };
    final knownScopedLabelIds = <String>{
      for (final label in primary.labels)
        if (label.isScoped) label.id,
      for (final label in secondary.labels)
        if (label.isScoped) label.id,
      if (baseline != null)
        for (final label in baseline.labels)
          if (label.isScoped) label.id,
    };
    final evictedFromQueueIds = <String>{};
    final latestCascadeDeletionByTask = <String, DateTime>{};
    final tasksAfterLabelStrip =
        TaskBoardReconciler.stripDeletedLabelsAndValidateReferences(
          taskOutcome.liveTasks,
          validLabelIds,
          labelOutcome.deletedLabelsById,
          baseline?.labels,
          knownScopedLabelIds: knownScopedLabelIds,
          evictedFromQueueOut: evictedFromQueueIds,
          boards: boards,
          latestDeletionByTaskOut: latestCascadeDeletionByTask,
          schemaVersion: schemaVersion,
        );
    final tasksAfterLocStrip =
        TaskBoardReconciler.stripDeletedLocationsFromTasksAndValidate(
          tasksAfterLabelStrip,
          validLocationIds,
          locationOutcome.deletedLocationsById,
          baseline?.locations,
          postCascadeLabelsById,
          latestDeletionByTaskOut: latestCascadeDeletionByTask,
        );

    final uncleanedAfterCascadesById = _applyCascadesToUncleanedTasks(
      uncleanedTasks: taskOutcome.uncleanedLiveTasksById.values.toList(),
      validLabelIds: validLabelIds,
      deletedLabelsById: labelOutcome.deletedLabelsById,
      baselineLabels: baseline?.labels,
      knownScopedLabelIds: knownScopedLabelIds,
      boards: boards,
      validLocationIds: validLocationIds,
      deletedLocationsById: locationOutcome.deletedLocationsById,
      baselineLocations: baseline?.locations,
      postCascadeLabelsById: postCascadeLabelsById,
      schemaVersion: schemaVersion,
    );

    final finalizedDeleted = finalizeDeletedBlock(
      leftGen >= rightGen ? leftGen : rightGen,
      taskOutcome.deletedTasksById,
      labelOutcome.deletedLabelsById,
      locationOutcome.retiredByUndelete ||
          labelOutcome.retiredByUndelete ||
          taskOutcome.retiredByUndelete,
      pruneExpiredDeleted,
      now,
      locationOutcome.deletedLocationsById,
    );
    final expiredStrippedTaskIds = <String>{};
    final tasksAfterExpiredCleanup = _stripExpiredTaskDependencies(
      tasksAfterLocStrip,
      taskOutcome.deletedTasksById,
      finalizedDeleted,
      now,
      strippedTaskIdsOut: expiredStrippedTaskIds,
    );
    final tasksAfterBlockCleanup =
        (schemaVersion == TdfSchemaVersion.v070 && applyPostMergeBlockCleanup)
        ? TaskBoardEvaluator.cleanupResolvedTaskBlocks(
            tasks: tasksAfterExpiredCleanup,
            deleted: finalizedDeleted,
            nowUtc: now,
          ).tasks
        : tasksAfterExpiredCleanup;

    final finalTasks = _assignFinalMergedTaskRevisions(
      tasksAfterCleanup: tasksAfterBlockCleanup,
      reconciledLiveTasks: taskOutcome.liveTasks,
      uncleanedAfterCascadesById: uncleanedAfterCascadesById,
      undeletedTaskIds: taskOutcome.undeletedTaskIds,
      latestCascadeDeletionByTask: latestCascadeDeletionByTask,
      expiredStrippedTaskIds: expiredStrippedTaskIds,
      boards: boards,
      now: now,
      schemaVersion: schemaVersion,
    );

    validateMergedGraphAndBounds(
      finalTasks,
      labelsAfterStrip,
      locationOutcome.liveLocations,
      schemaVersion,
    );

    final undeletedQueuedTaskIds = _resolveUndeletedQueuedTaskIds(
      primary,
      secondary,
      taskConflictResolutions,
      evictedFromQueueIds,
    );
    final mergedQueue = mergeQueueBlocks(
      primary,
      secondary,
      baseline?.queueBlock,
      undeletedQueuedTaskIds,
      finalTasks,
      evictedFromQueueIds: evictedFromQueueIds,
    );

    final mergedBoard = TaskBoard.evaluate(
      tasks: finalTasks,
      evaluationTime: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
      labels: labelsAfterStrip,
      locations: locationOutcome.liveLocations,
      deletedBlock: finalizedDeleted,
      queueBlock: mergedQueue,
      pruneExpiredCompleted: true,
    );
    AppLogger.event(
      LogLevel.info,
      LogTag.sync,
      'sync.merge',
      fields: <String, Object?>{
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

  /// Merges the `queue` blocks of [primary] and [secondary] with [baselineQueue] and reconciles against [mergedTasks] per Section 6.11.2.
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
      if (task == null || seenInQueue.contains(id)) continue;
      final isAddition =
          undeletedTaskIds.contains(id) ||
          (appendFromLoser && !baselineIdSet.contains(id));
      if (isAddition && seenInQueue.add(id)) concurrentAdditions.add(task);
    }

    concurrentAdditions.sort(_compareConcurrentQueuedTasks);
    reconciledIds.addAll(concurrentAdditions.map((task) => task.id));
    if (reconciledIds.length > TdfQueueBlock.maxQueueEntries) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged queue block exceeds MAX_QUEUE_ENTRIES (4096).',
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

  /// Recovers ambiguous local entities identified by [recoverTaskIds], [recoverLabelIds],
  /// and [recoverLocationIds] from [localBoard] into [sharedBoard] as new entities with
  /// freshly generated 10-character Base62 IDs, rewriting `labels`, `blocked`, and
  /// `condition location` references among recovered entities and stripping `blocked`
  /// references to non-recovered discarded tasks on surviving open tasks per Section 6.8.4.
  static TaskBoard recoverAmbiguousEntities({
    required TaskBoard localBoard,
    required TaskBoard sharedBoard,
    TaskBoard? baseline,
    Iterable<String> recoverTaskIds = const <String>[],
    Iterable<String> recoverLabelIds = const <String>[],
    Iterable<String> recoverLocationIds = const <String>[],
    required DateTime evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
    bool applyPostMergeBlockCleanup = true,
    TdfSchemaVersion schemaVersion = TdfSchemaVersion.v070,
  }) {
    final now = TaskItem.normalizeTimestamp(evaluationTime);
    final usedLocationIds = <String>{
      for (final location in localBoard.locations) location.id,
      for (final location in sharedBoard.locations) location.id,
      for (final record in localBoard.deletedBlock.locations) record.locationId,
      for (final record in sharedBoard.deletedBlock.locations)
        record.locationId,
    };
    final usedLabelIds = <String>{
      for (final label in localBoard.labels) label.id,
      for (final label in sharedBoard.labels) label.id,
      for (final record in localBoard.deletedBlock.labels) record.labelId,
      for (final record in sharedBoard.deletedBlock.labels) record.labelId,
    };
    final usedTaskIds = <String>{
      for (final task in localBoard.allTasks) task.id,
      for (final task in sharedBoard.allTasks) task.id,
      for (final record in localBoard.deletedBlock.tasks) record.taskId,
      for (final record in sharedBoard.deletedBlock.tasks) record.taskId,
    };

    final locationIdMap = <String, String>{};
    for (final oldLocId in <String>{...recoverLocationIds}) {
      final newId = generateLocationId(
        timestamp: now,
        existingIds: usedLocationIds,
      );
      usedLocationIds.add(newId);
      locationIdMap[oldLocId] = newId;
    }
    final labelIdMap = <String, String>{};
    for (final oldLabelId in <String>{...recoverLabelIds}) {
      final newId = generateLabelId(timestamp: now, existingIds: usedLabelIds);
      usedLabelIds.add(newId);
      labelIdMap[oldLabelId] = newId;
    }
    final taskIdMap = <String, String>{};
    for (final oldTaskId in <String>{...recoverTaskIds}) {
      final newId = generateTaskId(timestamp: now, existingIds: usedTaskIds);
      usedTaskIds.add(newId);
      taskIdMap[oldTaskId] = newId;
    }

    final sharedLocationIds = <String>{
      for (final location in sharedBoard.locations) location.id,
    };
    final sharedLabelIds = <String>{
      for (final label in sharedBoard.labels) label.id,
    };
    final sharedTaskIds = <String>{
      for (final task in sharedBoard.allTasks) task.id,
    };
    final discardedTaskIds = schemaVersion == TdfSchemaVersion.v070
        ? <String>{
            for (final task in localBoard.allTasks)
              if (!taskIdMap.containsKey(task.id) &&
                  !sharedTaskIds.contains(task.id))
                task.id,
          }
        : const <String>{};

    final adjustedLocations = <TdfLocation>[
      for (final location in localBoard.locations)
        if (locationIdMap[location.id] case final newId?)
          location.copyWith(
            id: newId,
            modifiedAt: TaskItem.nextModifiedTimestamp(
              now,
              location.effectiveModifiedAt,
            ),
          )
        else if (sharedLocationIds.contains(location.id))
          location,
    ];
    final adjustedLabels = <TdfLabel>[
      for (final label in localBoard.labels)
        if (labelIdMap[label.id] case final newId?)
          _rewriteRecoveredLabel(label, newId, locationIdMap, now)
        else if (sharedLabelIds.contains(label.id))
          _rewriteRecoveredLabel(label, label.id, locationIdMap, now),
    ];
    final adjustedTasks = <TaskItem>[
      for (final task in localBoard.allTasks)
        if (taskIdMap[task.id] case final newId?)
          _rewriteRecoveredTask(
            task,
            newId,
            labelIdMap,
            taskIdMap,
            locationIdMap,
            discardedTaskIds,
            now,
          )
        else if (sharedTaskIds.contains(task.id))
          _rewriteRecoveredTask(
            task,
            task.id,
            labelIdMap,
            taskIdMap,
            locationIdMap,
            discardedTaskIds,
            now,
          ),
    ];
    final adjustedQueueIds = <String>[
      for (final id in localBoard.queueBlock.taskIds)
        if (taskIdMap[id] case final mapped?)
          mapped
        else if (sharedTaskIds.contains(id))
          id,
    ];

    final preparedLocal = TaskBoard.evaluate(
      tasks: adjustedTasks,
      labels: adjustedLabels,
      locations: adjustedLocations,
      deletedBlock: localBoard.deletedBlock.copyWith(
        generation: sharedBoard.deletedBlock.generation,
      ),
      queueBlock: localBoard.queueBlock.copyWith(taskIds: adjustedQueueIds),
      evaluationTime: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
    );
    return merge(
      primary: preparedLocal,
      secondary: sharedBoard,
      baseline: baseline,
      acknowledgedGeneration: sharedBoard.deletedBlock.generation,
      evaluationTime: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
      applyPostMergeBlockCleanup: applyPostMergeBlockCleanup,
      schemaVersion: schemaVersion,
    );
  }

  /// Evaluates the 6-tier pipeline on [board] at [evaluationTime], optionally cleaning
  /// resolved open-task `suspended` and `blocked` directives when [applyPostMergeBlockCleanup]
  /// is `true` under `0.7.0`, while preserving untouched entity `modifiedAt` states.
  static TaskBoard stampAndNormalize(
    TaskBoard board, {
    required DateTime evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
    bool applyPostMergeBlockCleanup = true,
    TdfSchemaVersion schemaVersion = TdfSchemaVersion.v070,
  }) {
    final normalizedNow = TaskItem.normalizeTimestamp(evaluationTime);
    final tasksToEvaluate =
        (applyPostMergeBlockCleanup && schemaVersion == TdfSchemaVersion.v070)
        ? TaskBoardEvaluator.cleanupResolvedTaskBlocks(
            tasks: board.allTasks,
            deleted: board.deletedBlock,
            nowUtc: normalizedNow,
          ).tasks
        : board.allTasks;
    return TaskBoard.evaluate(
      tasks: tasksToEvaluate,
      evaluationTime: normalizedNow,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
      labels: board.labels,
      locations: board.locations,
      deletedBlock: board.deletedBlock,
      queueBlock: board.queueBlock,
      pruneExpiredCompleted: true,
    );
  }

  /// Validates the combined dependency graph for cycles and checks Section 7 resource bounds under [schemaVersion].
  static void validateMergedGraphAndBounds(
    List<TaskItem> tasks,
    List<TdfLabel> labels, [
    List<TdfLocation> locations = const <TdfLocation>[],
    TdfSchemaVersion schemaVersion = TdfSchemaVersion.v070,
  ]) {
    if (locations.length > maxTdfLocations) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged document exceeds MAX_LOCATIONS (200).',
      );
    }
    if (tasks.length + labels.length + locations.length + 2 >
        maxTdfBlocksPerDoc) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged document exceeds MAX_BLOCKS_PER_DOC (4096).',
      );
    }
    final maxStatements = schemaVersion == TdfSchemaVersion.v060
        ? maxTdfLegacy060StmtsPerBlock
        : maxTdfStmtsPerBlock;
    for (final label in labels) {
      _validateLabelBounds(label, maxStatements);
    }
    for (final task in tasks) {
      _validateTaskBounds(task, maxStatements);
    }
    final taskMap = <String, TaskItem>{for (final task in tasks) task.id: task};
    if (_hasDependencyCycle(taskMap)) {
      _throwTdf(
        TdfErrorKind.circularDependency,
        'Merged document contains a circular task dependency.',
      );
    }
  }

  /// Applies Section 6.7.8 label and location deletion cascades to [uncleanedTasks] for Section 6.7.6 comparison.
  static Map<String, TaskItem> _applyCascadesToUncleanedTasks({
    required List<TaskItem> uncleanedTasks,
    required Set<String> validLabelIds,
    required Map<String, TdfDeletedLabelRecord> deletedLabelsById,
    required List<TdfLabel>? baselineLabels,
    required Set<String> knownScopedLabelIds,
    required (TaskBoard, TaskBoard, TaskBoard?) boards,
    required Set<String> validLocationIds,
    required Map<String, TdfDeletedLocationRecord> deletedLocationsById,
    required List<TdfLocation>? baselineLocations,
    required Map<String, TdfLabel> postCascadeLabelsById,
    required TdfSchemaVersion schemaVersion,
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
          knownScopedLabelIds: knownScopedLabelIds,
          boards: boards,
          schemaVersion: schemaVersion,
        );
    final afterLocations =
        TaskBoardReconciler.stripDeletedLocationsFromTasksAndValidate(
          afterLabels,
          validLocationIds,
          deletedLocationsById,
          baselineLocations,
          postCascadeLabelsById,
        );
    return <String, TaskItem>{for (final task in afterLocations) task.id: task};
  }

  /// Assigns deterministic Section 6.7.6 revisions across [tasksAfterCleanup].
  static List<TaskItem> _assignFinalMergedTaskRevisions({
    required List<TaskItem> tasksAfterCleanup,
    required List<TaskItem> reconciledLiveTasks,
    required Map<String, TaskItem> uncleanedAfterCascadesById,
    required Set<String> undeletedTaskIds,
    required Map<String, DateTime> latestCascadeDeletionByTask,
    required Set<String> expiredStrippedTaskIds,
    required (TaskBoard, TaskBoard, TaskBoard?) boards,
    required DateTime now,
    required TdfSchemaVersion schemaVersion,
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
          latestCascadeDeletion: latestCascadeDeletionByTask[task.id],
          expiredStripped: expiredStrippedTaskIds.contains(task.id),
          now: now,
          schemaVersion: schemaVersion,
        ),
    ];
  }

  /// Assigns the final Section 6.7.6 `modifiedAt` timestamp for a single surviving [finalTask].
  static TaskItem _assignSingleFinalTaskRevision({
    required TaskItem finalTask,
    required TaskItem? reconciledTask,
    required TaskItem? uncleanedTask,
    required TaskItem? primaryTask,
    required TaskItem? secondaryTask,
    required TaskItem? baselineTask,
    required bool wasUndeleted,
    required DateTime? latestCascadeDeletion,
    required bool expiredStripped,
    required DateTime now,
    required TdfSchemaVersion schemaVersion,
  }) {
    if (wasUndeleted) {
      final baseDecision = reconciledTask?.effectiveModifiedAt ?? now;
      if (latestCascadeDeletion != null &&
          !latestCascadeDeletion.isBefore(baseDecision)) {
        final bumpedCascade = _checkedBumpPlusOneSecond(latestCascadeDeletion);
        final withNow = now.isAfter(bumpedCascade) ? now : bumpedCascade;
        return finalTask.copyWith(modifiedAt: _checkedTimestamp(withNow));
      }
      return finalTask.copyWith(modifiedAt: baseDecision);
    }

    if (primaryTask != null && secondaryTask != null) {
      final winner =
          TdfPayloadComparison.compareTaskVersions(
                primaryTask,
                secondaryTask,
                schemaVersion: schemaVersion,
              ) >=
              0
          ? primaryTask
          : secondaryTask;
      final referenceExisting =
          (baselineTask != null &&
              TdfPayloadComparison.compareTaskVersions(
                    baselineTask,
                    winner,
                    schemaVersion: schemaVersion,
                  ) >
                  0)
          ? baselineTask
          : winner;
      final cascadeNotNewer =
          latestCascadeDeletion == null ||
          !latestCascadeDeletion.isAfter(referenceExisting.effectiveModifiedAt);
      if (cascadeNotNewer &&
          !expiredStripped &&
          referenceExisting.completions == finalTask.completions &&
          TdfPayloadComparison.compareTaskPayloads(
                referenceExisting,
                finalTask,
                schemaVersion: schemaVersion,
              ) ==
              0) {
        return finalTask.copyWith(
          modifiedAt: referenceExisting.modifiedAt,
          clearModifiedAt: referenceExisting.modifiedAt == null,
        );
      }

      var maxObserved = _laterDate(
        primaryTask.effectiveModifiedAt,
        secondaryTask.effectiveModifiedAt,
      );
      maxObserved = _laterDate(maxObserved, baselineTask?.effectiveModifiedAt);
      maxObserved = _laterDate(maxObserved, latestCascadeDeletion);
      final bumped = _checkedBumpPlusOneSecond(maxObserved);
      if (!expiredStripped &&
          uncleanedTask != null &&
          TdfPayloadComparison.compareTaskPayloads(
                finalTask,
                uncleanedTask,
                schemaVersion: schemaVersion,
              ) ==
              0) {
        return finalTask.copyWith(modifiedAt: bumped);
      }
      final withNow = now.isAfter(bumped) ? now : bumped;
      return finalTask.copyWith(modifiedAt: _checkedTimestamp(withNow));
    }

    final sourceTask = primaryTask ?? secondaryTask;
    if (sourceTask == null) {
      return finalTask;
    }
    final cascadeNotNewer =
        latestCascadeDeletion == null ||
        !latestCascadeDeletion.isAfter(sourceTask.effectiveModifiedAt);
    if (cascadeNotNewer &&
        !expiredStripped &&
        TdfPayloadComparison.compareTaskPayloads(
              sourceTask,
              finalTask,
              schemaVersion: schemaVersion,
            ) ==
            0) {
      return finalTask.copyWith(
        modifiedAt: sourceTask.modifiedAt,
        clearModifiedAt: sourceTask.modifiedAt == null,
      );
    }
    final maxObserved = _laterDate(
      sourceTask.effectiveModifiedAt,
      latestCascadeDeletion,
    );
    final bumped = _checkedBumpPlusOneSecond(maxObserved);
    if (!expiredStripped &&
        uncleanedTask != null &&
        TdfPayloadComparison.compareTaskPayloads(
              finalTask,
              uncleanedTask,
              schemaVersion: schemaVersion,
            ) ==
            0) {
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

  /// Orders concurrent queue additions by ascending UTC `createdAt`, then ascending ASCII `id` per Section 6.11.2.
  static int _compareConcurrentQueuedTasks(TaskItem left, TaskItem right) {
    final createdCmp = left.createdAt.compareTo(right.createdAt);
    return createdCmp != 0 ? createdCmp : left.id.compareTo(right.id);
  }

  /// Returns whether any `LocationTaskCondition` in [conditions] references a key in [locationIdMap].
  static bool _conditionsReferenceAny(
    List<TaskCondition> conditions,
    Map<String, String> locationIdMap,
  ) {
    if (conditions.isEmpty || locationIdMap.isEmpty) {
      return false;
    }
    for (final rule in conditions) {
      if (rule is LocationTaskCondition &&
          rule.locationIds.any(locationIdMap.containsKey)) {
        return true;
      }
    }
    return false;
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

  /// Resolves the set of undeleted task IDs that were present in the surviving live side's `queue` block per Section 6.8.2.
  static Set<String> _resolveUndeletedQueuedTaskIds(
    TaskBoard primary,
    TaskBoard secondary,
    Map<String, TdfDeletionResolution> taskConflictResolutions,
    Set<String> evictedFromQueueIds,
  ) {
    final primaryQueued = primary.queueBlock.taskIds.toSet();
    final secondaryQueued = secondary.queueBlock.taskIds.toSet();
    final result = <String>{};
    for (final entry in taskConflictResolutions.entries) {
      if (entry.value != TdfDeletionResolution.undelete) continue;
      final id = entry.key;
      if (evictedFromQueueIds.contains(id)) continue;
      final inSurvivingQueue = primary.findTask(id) != null
          ? primaryQueued.contains(id)
          : secondaryQueued.contains(id);
      if (inSurvivingQueue) {
        result.add(id);
      }
    }
    return result;
  }

  /// Rewrites `LocationTaskCondition.locationIds` in [conditions] using [locationIdMap].
  static List<TaskCondition> _rewriteConditionLocations(
    List<TaskCondition> conditions,
    Map<String, String> locationIdMap,
  ) {
    if (conditions.isEmpty || locationIdMap.isEmpty) {
      return conditions;
    }
    return <TaskCondition>[
      for (final rule in conditions)
        if (rule is LocationTaskCondition && rule.locationIds.isNotEmpty)
          LocationTaskCondition.fromIds(<String>[
            for (final locationId in rule.locationIds)
              locationIdMap[locationId] ?? locationId,
          ])
        else
          rule,
    ];
  }

  /// Rewrites a recovered or surviving [label] with [newId] and remapped `condition location` references per Section 6.8.4.
  static TdfLabel _rewriteRecoveredLabel(
    TdfLabel label,
    String newId,
    Map<String, String> locationIdMap,
    DateTime now,
  ) {
    final idChanged = newId != label.id;
    final condChanged = _conditionsReferenceAny(
      label.conditions,
      locationIdMap,
    );
    if (!idChanged && !condChanged) {
      return label;
    }
    return label.copyWith(
      id: newId,
      modifiedAt: TaskItem.nextModifiedTimestamp(
        now,
        label.effectiveModifiedAt,
      ),
      conditions: condChanged
          ? _rewriteConditionLocations(label.conditions, locationIdMap)
          : label.conditions,
    );
  }

  /// Rewrites a recovered or surviving [task] with [newId], remapped references, and stripped [discardedTaskIds] on open tasks per Section 6.8.4.
  static TaskItem _rewriteRecoveredTask(
    TaskItem task,
    String newId,
    Map<String, String> labelIdMap,
    Map<String, String> taskIdMap,
    Map<String, String> locationIdMap,
    Set<String> discardedTaskIds,
    DateTime now,
  ) {
    final isOpen = !task.isCompleted && task.completedAt == null;
    final idChanged = newId != task.id;
    final labelsChanged = task.labelIds.any(labelIdMap.containsKey);
    final depsChanged = task.dependencies.any(
      (dependency) => taskIdMap.containsKey(dependency.taskId),
    );
    final discardedDepsStripped =
        isOpen &&
        discardedTaskIds.isNotEmpty &&
        task.dependencies.any(
          (dependency) => discardedTaskIds.contains(dependency.taskId),
        );
    final condChanged = _conditionsReferenceAny(task.conditions, locationIdMap);
    if (!idChanged &&
        !labelsChanged &&
        !depsChanged &&
        !discardedDepsStripped &&
        !condChanged) {
      return task;
    }
    final mappedDeps = <TdfTaskDependency>[
      for (final dependency in task.dependencies)
        if (!isOpen || !discardedTaskIds.contains(dependency.taskId))
          TdfTaskDependency(
            taskId: taskIdMap[dependency.taskId] ?? dependency.taskId,
            requiredCompletion: dependency.requiredCompletion,
          ),
    ];
    return task.copyWith(
      id: newId,
      modifiedAt: TaskItem.nextModifiedTimestamp(now, task.effectiveModifiedAt),
      labelIds: <String>[
        for (final labelId in task.labelIds) labelIdMap[labelId] ?? labelId,
      ],
      conditions: condChanged
          ? _rewriteConditionLocations(task.conditions, locationIdMap)
          : task.conditions,
      dependencies: mappedDeps,
      blockedByTaskIds: <String>[
        for (final dependency in mappedDeps) dependency.taskId,
      ],
    );
  }

  /// Strips [expiredTaskIds] from a single [task]'s `dependencies` and advances `modifiedAt` if changed.
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

  /// Strips `blocked` references targeting task deletion records that expired during [afterPrune] per Section 6.8.3.
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

  /// Throws a [TdfException] at line 1 with [kind] and [message].
  static Never _throwTdf(TdfErrorKind kind, String message) =>
      throw TdfException(kind: kind, line: 1, message: message);

  /// Validates Section 7 `links`, location reference, and statement count bounds on [label].
  static void _validateLabelBounds(TdfLabel label, int maxStatements) {
    if (label.links.length > maxTdfLinksPerLabel) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged label "${label.id}" exceeds MAX_LINKS_PER_LABEL (20).',
      );
    }
    if (_countLocationRefs(label.conditions) > maxTdfLocationRefsPerEntity) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged label "${label.id}" exceeds MAX_LOCATION_REFS_PER_ENTITY (63).',
      );
    }
    if (label.canonicalDirectChildStatementCount > maxStatements) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged label "${label.id}" exceeds MAX_STMTS_PER_BLOCK ($maxStatements).',
      );
    }
  }

  /// Validates Section 7 directive argument, link, history, and statement count bounds on [task].
  static void _validateTaskBounds(TaskItem task, int maxStatements) {
    if (task.labelIds.length > maxTdfArgsPerStmt) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged task "${task.id}" exceeds MAX_ARGS_PER_STMT (64) on labels.',
      );
    }
    if (task.dependencies.length > maxTdfArgsPerStmt) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged task "${task.id}" exceeds MAX_ARGS_PER_STMT (64) on blocked.',
      );
    }
    if (_countLocationRefs(task.conditions) > maxTdfLocationRefsPerEntity) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged task "${task.id}" exceeds MAX_LOCATION_REFS_PER_ENTITY (63).',
      );
    }
    if (task.links.length > maxTdfLinksPerLabel) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged task "${task.id}" exceeds MAX_LINKS_PER_TASK (20).',
      );
    }
    if (task.history.length > maxTdfHistoryPerTask) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged task "${task.id}" exceeds MAX_HISTORY_PER_TASK (500).',
      );
    }
    if (task.subtasks.length > maxStatements ||
        task.canonicalDirectChildStatementCount > maxStatements) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged task "${task.id}" exceeds MAX_STMTS_PER_BLOCK ($maxStatements).',
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
      if (targetId == currentId) return true;
      if (!taskMap.containsKey(targetId)) continue;
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
