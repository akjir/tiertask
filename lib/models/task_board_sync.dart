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
import 'tdf_metadata.dart';
import 'tdf_payload_comparison.dart';
import 'tdf_sync_metadata.dart';
import 'tdf_timezone.dart';

/// Stateless entity-level synchronization, three-way merge, deletion record
/// reconciliation, and shared queue merge engine for [TaskBoard] documents
/// per `TDF_SPEC.md` Sections 6.7, 6.8, 6.9.5, and 6.11.2.
@immutable
class TaskBoardSync {
  /// Prevents instantiation of this stateless helper class.
  const TaskBoardSync._();

  /// Combines active deletion records from [primary] and [secondary], discarding old acknowledged records when one side advanced generation.
  static ({
    Map<String, TdfDeletedTaskRecord> tasks,
    Map<String, TdfDeletedLabelRecord> labels,
  })
  combineInitialDeletedRecords(
    TdfDeletedBlock primary,
    TdfDeletedBlock secondary,
    TdfDeletedBlock? baseline,
    Map<String, DateTime> deletedLabelTimestamps,
  ) {
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
    return (tasks: taskRecords, labels: labelRecords);
  }

  /// Prunes expired deletion records (> `2,592,000` seconds) and increments `generation` once when records are retired per Section 6.8.3.
  static TdfDeletedBlock finalizeDeletedBlock(
    int baseGeneration,
    Map<String, TdfDeletedTaskRecord> deletedTasks,
    Map<String, TdfDeletedLabelRecord> deletedLabels,
    bool retiredByUndelete,
    bool pruneExpired,
    DateTime now,
  ) {
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
    if (activeTasks.length + activeLabels.length >
        TdfDeletedBlock.maxDeletedRecords) {
      _throwTdf(
        TdfErrorKind.limitExceeded,
        'Merged deleted block exceeds MAX_DELETED_RECORDS (4096).',
      );
    }

    final anyExpired =
        activeTasks.length != deletedTasks.length ||
        activeLabels.length != deletedLabels.length;
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
    );
  }

  /// Merges [primary] and [secondary] entity-by-entity (`label`, `task`, `deleted`,
  /// and `queue` blocks) using [baseline], [acknowledgedGeneration],
  /// [deletedLabelTimestamps], [taskConflictResolutions], and [labelConflictResolutions],
  /// and evaluates the 6-tier pipeline at [evaluationTime].
  static TaskBoard merge({
    required TaskBoard primary,
    required TaskBoard secondary,
    TaskBoard? baseline,
    int? acknowledgedGeneration,
    Map<String, DateTime> deletedLabelTimestamps = const {},
    Map<String, TdfDeletionResolution> taskConflictResolutions = const {},
    Map<String, TdfDeletionResolution> labelConflictResolutions = const {},
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
    );
    final labelOutcome = TaskBoardReconciler.reconcileLabels(
      boards,
      initialDeleted.labels,
      labelConflictResolutions,
      options,
    );
    final taskOutcome = TaskBoardReconciler.reconcileTasks(
      boards,
      initialDeleted.tasks,
      taskConflictResolutions,
      options,
    );
    TaskBoardReconciler.checkSyncOutcomes(labelOutcome, taskOutcome);

    final validLabelIds = <String>{
      for (final label in labelOutcome.liveLabels) label.id,
    };
    final tasksAfterStrip =
        TaskBoardReconciler.stripDeletedLabelsAndValidateReferences(
          taskOutcome.liveTasks,
          validLabelIds,
          labelOutcome.deletedLabelsById,
          baseline?.labels,
        );
    validateMergedGraphAndBounds(tasksAfterStrip, labelOutcome.liveLabels);

    final finalizedDeleted = finalizeDeletedBlock(
      leftGen >= rightGen ? leftGen : rightGen,
      taskOutcome.deletedTasksById,
      labelOutcome.deletedLabelsById,
      labelOutcome.retiredByUndelete || taskOutcome.retiredByUndelete,
      pruneExpiredDeleted,
      now,
    );
    final undeletedTaskIds = <String>{
      for (final entry in taskConflictResolutions.entries)
        if (entry.value == TdfDeletionResolution.undelete) entry.key,
    };
    final mergedQueue = mergeQueueBlocks(
      primary,
      secondary,
      baseline?.queueBlock,
      undeletedTaskIds,
      tasksAfterStrip,
    );

    final mergedBoard = TaskBoard.evaluate(
      tasks: tasksAfterStrip,
      evaluationTime: now,
      localEvaluationTime: localEvaluationTime,
      labels: labelOutcome.liveLabels,
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
    List<TaskItem> mergedTasks,
  ) {
    final primaryQueue = primary.queueBlock;
    final secondaryQueue = secondary.queueBlock;
    final openById = <String, TaskItem>{
      for (final task in mergedTasks)
        if (!task.isCompleted && task.completedAt == null) task.id: task,
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

  /// Recovers ambiguous local entities identified by [recoverTaskIds] and [recoverLabelIds]
  /// from [localBoard] into [sharedBoard] as new entities with freshly generated 10-character
  /// Base62 IDs, rewriting `labels` and `blocked` references among recovered entities per
  /// `TDF_SPEC.md` Section 6.8.4.
  static TaskBoard recoverAmbiguousEntities({
    required TaskBoard localBoard,
    required TaskBoard sharedBoard,
    TaskBoard? baseline,
    Iterable<String> recoverTaskIds = const <String>[],
    Iterable<String> recoverLabelIds = const <String>[],
    required DateTime evaluationTime,
    DateTime? localEvaluationTime,
  }) {
    final now = TaskItem.normalizeTimestamp(evaluationTime);
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

    final sharedLabelIds = <String>{
      for (final label in sharedBoard.labels) label.id,
    };
    final sharedTaskIds = <String>{
      for (final task in sharedBoard.allTasks) task.id,
    };

    final adjustedLabels = <TdfLabel>[
      for (final label in localBoard.labels)
        if (labelIdMap[label.id] case final newId?)
          label.copyWith(
            id: newId,
            modifiedAt: TaskItem.nextModifiedTimestamp(
              now,
              label.effectiveModifiedAt,
            ),
          )
        else if (sharedLabelIds.contains(label.id))
          label,
    ];
    final adjustedTasks = <TaskItem>[
      for (final task in localBoard.allTasks)
        if (taskIdMap[task.id] case final newId?)
          _rewriteRecoveredTask(task, newId, labelIdMap, taskIdMap, now)
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
  /// per `TDF_SPEC.md` Section 6.7.1 and 6.7.4.
  static TaskBoard stampAndNormalize(
    TaskBoard board, {
    required DateTime evaluationTime,
    DateTime? localEvaluationTime,
  }) => TaskBoard.evaluate(
    tasks: board.allTasks,
    evaluationTime: TaskItem.normalizeTimestamp(evaluationTime),
    localEvaluationTime: localEvaluationTime,
    labels: board.labels,
    deletedBlock: board.deletedBlock,
    queueBlock: board.queueBlock,
    pruneExpiredCompleted: true,
  );

  /// Validates the combined dependency graph for cycles and checks Section 7 resource bounds.
  static void validateMergedGraphAndBounds(
    List<TaskItem> tasks,
    List<TdfLabel> labels,
  ) {
    if (tasks.length + labels.length + 2 > maxTdfBlocksPerDoc) {
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

  /// Rewrites a recovered [task] with [newId] and remapped `labelIds` and `dependencies` per Section 6.8.4.
  static TaskItem _rewriteRecoveredTask(
    TaskItem task,
    String newId,
    Map<String, String> labelIdMap,
    Map<String, String> taskIdMap,
    DateTime now,
  ) => task.copyWith(
    id: newId,
    modifiedAt: TaskItem.nextModifiedTimestamp(now, task.effectiveModifiedAt),
    labelIds: <String>[
      for (final labelId in task.labelIds) labelIdMap[labelId] ?? labelId,
    ],
    dependencies: <TdfTaskDependency>[
      for (final dependency in task.dependencies)
        TdfTaskDependency(
          taskId: taskIdMap[dependency.taskId] ?? dependency.taskId,
          requiredCompletion: dependency.requiredCompletion,
        ),
    ],
  );

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
