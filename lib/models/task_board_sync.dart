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
/// per `TDF_SPEC_0.6.0.md` Sections 6.7, 6.8, 6.9.5, and 6.11.2.
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
        'Merged deleted block exceeds MAX_DELETED_RECORDS (4096).',
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
    bool pruneExpiredDeleted = true,
    bool requireAcknowledgedGeneration = false,
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
      for (final loc in locationOutcome.liveLocations) loc.id,
    };
    final tombstonedLocationIds = <String>{
      ...locationOutcome.deletedLocationsById.keys,
      if (baseline != null)
        for (final loc in baseline.locations)
          if (!validLocationIds.contains(loc.id)) loc.id,
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
      validLabelIds: validLabelIds,
      postCascadeLabelsById: previewLabelsById,
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
    final tasksAfterLabelStrip =
        TaskBoardReconciler.stripDeletedLabelsAndValidateReferences(
          taskOutcome.liveTasks,
          validLabelIds,
          labelOutcome.deletedLabelsById,
          baseline?.labels,
          knownScopedLabelIds: knownScopedLabelIds,
          evictedFromQueueOut: evictedFromQueueIds,
        );
    final tasksAfterLocStrip =
        TaskBoardReconciler.stripDeletedLocationsFromTasksAndValidate(
          tasksAfterLabelStrip,
          validLocationIds,
          locationOutcome.deletedLocationsById,
          baseline?.locations,
          postCascadeLabelsById,
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
    final tasksAfterExpiredCleanup = _stripExpiredTaskDependencies(
      tasksAfterLocStrip,
      taskOutcome.deletedTasksById,
      finalizedDeleted,
      now,
    );
    validateMergedGraphAndBounds(
      tasksAfterExpiredCleanup,
      labelsAfterStrip,
      locationOutcome.liveLocations,
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
      tasksAfterExpiredCleanup,
      evictedFromQueueIds: evictedFromQueueIds,
    );

    final mergedBoard = TaskBoard.evaluate(
      tasks: tasksAfterExpiredCleanup,
      evaluationTime: now,
      localEvaluationTime: localEvaluationTime,
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
  /// `condition location` references among recovered entities per `TDF_SPEC_0.6.0.md` Section 6.8.4.
  static TaskBoard recoverAmbiguousEntities({
    required TaskBoard localBoard,
    required TaskBoard sharedBoard,
    TaskBoard? baseline,
    Iterable<String> recoverTaskIds = const <String>[],
    Iterable<String> recoverLabelIds = const <String>[],
    Iterable<String> recoverLocationIds = const <String>[],
    required DateTime evaluationTime,
    DateTime? localEvaluationTime,
  }) {
    final now = TaskItem.normalizeTimestamp(evaluationTime);
    final usedLocationIds = <String>{
      for (final loc in localBoard.locations) loc.id,
      for (final loc in sharedBoard.locations) loc.id,
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
      for (final loc in sharedBoard.locations) loc.id,
    };
    final sharedLabelIds = <String>{
      for (final label in sharedBoard.labels) label.id,
    };
    final sharedTaskIds = <String>{
      for (final task in sharedBoard.allTasks) task.id,
    };

    final adjustedLocations = <TdfLocation>[
      for (final loc in localBoard.locations)
        if (locationIdMap[loc.id] case final newId?)
          loc.copyWith(
            id: newId,
            modifiedAt: TaskItem.nextModifiedTimestamp(
              now,
              loc.effectiveModifiedAt,
            ),
          )
        else if (sharedLocationIds.contains(loc.id))
          loc,
    ];
    final adjustedLabels = <TdfLabel>[
      for (final label in localBoard.labels)
        if (labelIdMap[label.id] case final newId?)
          _rewriteRecoveredLabel(label, newId, locationIdMap, now)
        else if (sharedLabelIds.contains(label.id))
          label,
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
            now,
          )
        else if (sharedTaskIds.contains(task.id))
          task,
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
    );
    return merge(
      primary: preparedLocal,
      secondary: sharedBoard,
      baseline: baseline,
      acknowledgedGeneration: sharedBoard.deletedBlock.generation,
      evaluationTime: now,
      localEvaluationTime: localEvaluationTime,
    );
  }

  /// Evaluates the 6-tier pipeline on [board] at [evaluationTime] while preserving
  /// each entity's existing `modifiedAt` state (including omitted `modified` directives)
  /// per `TDF_SPEC_0.6.0.md` Section 6.7.1 and 6.7.4.
  static TaskBoard stampAndNormalize(
    TaskBoard board, {
    required DateTime evaluationTime,
    DateTime? localEvaluationTime,
  }) => TaskBoard.evaluate(
    tasks: board.allTasks,
    evaluationTime: TaskItem.normalizeTimestamp(evaluationTime),
    localEvaluationTime: localEvaluationTime,
    labels: board.labels,
    locations: board.locations,
    deletedBlock: board.deletedBlock,
    queueBlock: board.queueBlock,
    pruneExpiredCompleted: true,
  );

  /// Validates the combined dependency graph for cycles and checks Section 7 resource bounds.
  static void validateMergedGraphAndBounds(
    List<TaskItem> tasks,
    List<TdfLabel> labels, [
    List<TdfLocation> locations = const <TdfLocation>[],
  ]) {
    if (tasks.length + labels.length + locations.length + 2 >
        maxTdfBlocksPerDoc) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged document exceeds MAX_BLOCKS_PER_DOC (4096).',
      );
    }
    final taskMap = <String, TaskItem>{for (final task in tasks) task.id: task};
    if (_hasDependencyCycle(taskMap)) {
      _throwTdf(
        TdfErrorKind.circularDependency,
        'Merged document contains a circular task dependency.',
      );
    }
  }

  /// Orders concurrent queue additions by ascending UTC `createdAt`, then ascending ASCII `id` per Section 6.11.2.
  static int _compareConcurrentQueuedTasks(TaskItem left, TaskItem right) {
    final createdCmp = left.createdAt.compareTo(right.createdAt);
    return createdCmp != 0 ? createdCmp : left.id.compareTo(right.id);
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
            for (final locId in rule.locationIds) locationIdMap[locId] ?? locId,
          ])
        else
          rule,
    ];
  }

  /// Rewrites a recovered [label] with [newId] and remapped `condition location` references per Section 6.8.4.
  static TdfLabel _rewriteRecoveredLabel(
    TdfLabel label,
    String newId,
    Map<String, String> locationIdMap,
    DateTime now,
  ) => label.copyWith(
    id: newId,
    modifiedAt: TaskItem.nextModifiedTimestamp(now, label.effectiveModifiedAt),
    conditions: _rewriteConditionLocations(label.conditions, locationIdMap),
  );

  /// Rewrites a recovered [task] with [newId] and remapped `labelIds`, `dependencies`, and `condition location` references per Section 6.8.4.
  static TaskItem _rewriteRecoveredTask(
    TaskItem task,
    String newId,
    Map<String, String> labelIdMap,
    Map<String, String> taskIdMap,
    Map<String, String> locationIdMap,
    DateTime now,
  ) => task.copyWith(
    id: newId,
    modifiedAt: TaskItem.nextModifiedTimestamp(now, task.effectiveModifiedAt),
    labelIds: <String>[
      for (final labelId in task.labelIds) labelIdMap[labelId] ?? labelId,
    ],
    conditions: _rewriteConditionLocations(task.conditions, locationIdMap),
    dependencies: <TdfTaskDependency>[
      for (final dependency in task.dependencies)
        TdfTaskDependency(
          taskId: taskIdMap[dependency.taskId] ?? dependency.taskId,
          requiredCompletion: dependency.requiredCompletion,
        ),
    ],
  );

  /// Strips `blocked` references targeting task deletion records that expired during [afterPrune] per Section 6.8.3.
  static List<TaskItem> _stripExpiredTaskDependencies(
    List<TaskItem> tasks,
    Map<String, TdfDeletedTaskRecord> beforePrune,
    TdfDeletedBlock afterPrune,
    DateTime now,
  ) {
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
        _stripExpiredDepsFromSingleTask(task, expiredTaskIds, now),
    ];
  }

  /// Strips [expiredTaskIds] from a single [task]'s `dependencies` and advances `modifiedAt` if changed.
  static TaskItem _stripExpiredDepsFromSingleTask(
    TaskItem task,
    Set<String> expiredTaskIds,
    DateTime now,
  ) {
    if (task.dependencies.isEmpty) {
      return task;
    }
    final retained = <TdfTaskDependency>[
      for (final dep in task.dependencies)
        if (!expiredTaskIds.contains(dep.taskId)) dep,
    ];
    if (retained.length == task.dependencies.length) {
      return task;
    }
    return task.copyWith(
      dependencies: retained,
      blockedByTaskIds: <String>[for (final dep in retained) dep.taskId],
      modifiedAt: TaskItem.nextModifiedTimestamp(now, task.effectiveModifiedAt),
    );
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
