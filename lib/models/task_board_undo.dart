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

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../services/app_logger.dart';
import 'task_board.dart';
import 'task_board_evaluator.dart';
import 'task_item.dart';
import 'tdf_error.dart';
import 'tdf_location.dart';
import 'tdf_metadata.dart';
import 'tdf_sync_metadata.dart';
import 'tdf_timezone.dart';

/// Classifies an undoable user task action.
enum TaskUndoActionKind {
  /// Direct task completion or `subtasks auto-finish` completion.
  complete,

  /// Active task step-down downgrade (`Focus -> Ready`, `Ready -> Planned`, `Planned -> Someday`).
  downgrade,

  /// Task deletion with tombstone creation.
  delete,
}

/// Stateless helper capturing and reversing single-task mutations on [TaskBoard]
/// while preserving `spec/TDF_SPEC_0.6.0.md` monotonic completion, revision,
/// queue, and deletion-generation invariants.
@immutable
class TaskBoardUndo {
  const TaskBoardUndo._();

  /// Maximum number of retained undo entries in a single workspace session (`10`).
  static const int maxUndoEntries = 10;

  /// Applies [entry] onto [currentBoard] at [utcNow], or returns `null` when
  /// the reversal is no longer applicable or violates a TDF resource bound.
  static TaskUndoOutcome? apply(
    TaskBoard currentBoard,
    TaskUndoEntry entry, {
    required DateTime utcNow,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  }) {
    final now = TaskItem.normalizeTimestamp(utcNow);
    if (!TdfCalendar.isWithinTimestampBounds(now)) {
      _logSkipped(entry, 'timestamp_out_of_bounds');
      return null;
    }
    return switch (entry.kind) {
      TaskUndoActionKind.complete => _applyComplete(
        currentBoard,
        entry,
        now,
        localEvaluationTime,
        timeZone,
      ),
      TaskUndoActionKind.downgrade => _applyDowngrade(
        currentBoard,
        entry,
        now,
        localEvaluationTime,
        timeZone,
      ),
      TaskUndoActionKind.delete => _applyDelete(
        currentBoard,
        entry,
        now,
        localEvaluationTime,
        timeZone,
      ),
    };
  }

  /// Captures a pre-mutation [TaskUndoEntry] from [boardBefore] and [taskBefore].
  static TaskUndoEntry capture({
    required int sequence,
    required TaskUndoActionKind kind,
    required TaskBoard boardBefore,
    required TaskItem taskBefore,
  }) {
    final labelMap = <String, TdfLabel>{
      for (final label in boardBefore.labels) label.id: label,
    };
    final blockedDependents = kind == TaskUndoActionKind.complete
        ? _collectPreviouslyBlockedDependents(boardBefore, taskBefore)
        : const <String>{};
    return TaskUndoEntry(
      sequence: sequence,
      kind: kind,
      snapshotTask: taskBefore,
      wasQueued: boardBefore.queueBlock.taskIds.contains(taskBefore.id),
      queueOrderSnapshot: boardBefore.queueBlock.taskIds,
      hadOnlyScopedLabels: TaskBoardEvaluator.isRestrictedFromGlobalView(
        taskBefore,
        labelMap,
      ),
      previouslyBlockedDependentIds: blockedDependents,
    );
  }

  /// Reverses a direct or `subtasks auto-finish` task completion on [currentBoard].
  static TaskUndoOutcome? _applyComplete(
    TaskBoard currentBoard,
    TaskUndoEntry entry,
    DateTime now,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  ) {
    final snapshotTask = entry.snapshotTask;
    final currentTask = currentBoard.findTask(snapshotTask.id);
    if (currentTask == null) {
      _logSkipped(entry, 'task_missing');
      return null;
    }

    final validLabelIds = <String>{
      for (final label in currentBoard.labels) label.id,
    };
    final validLocationIds = <String>{
      for (final location in currentBoard.locations) location.id,
    };
    final labelsWithLocation = _collectLabelsWithLocationRules(
      currentBoard.labels,
      validLocationIds,
    );
    final retainedLabels = <String>[
      for (final labelId in currentTask.labelIds)
        if (validLabelIds.contains(labelId)) labelId,
    ];
    final evictedByScopedDeletion =
        entry.hadOnlyScopedLabels && retainedLabels.isEmpty;
    final sanitizedConditions = _sanitizeConditions(
      currentTask.conditions,
      retainedLabels,
      validLocationIds,
      labelsWithLocation,
    );

    final baseRevision = _maxDateTime(
      currentTask.effectiveModifiedAt,
      snapshotTask.effectiveModifiedAt,
    );
    final nextModified = _tryNextTimestamp(now, baseRevision);
    if (nextModified == null) {
      _logSkipped(entry, 'timestamp_out_of_bounds');
      return null;
    }

    final restoredCompletions = math.max(
      snapshotTask.completions,
      currentTask.completions,
    );
    final restoredTask = currentTask.copyWith(
      isCompleted: false,
      clearCompletedAt: true,
      completions: restoredCompletions,
      isPriority: evictedByScopedDeletion ? false : snapshotTask.isPriority,
      labelIds: retainedLabels,
      conditions: sanitizedConditions,
      suspendedAt: snapshotTask.suspendedAt,
      clearSuspendedAt: snapshotTask.suspendedAt == null,
      isSuspendedForever: snapshotTask.isSuspendedForever,
      dueAt: snapshotTask.dueAt,
      clearDueAt: snapshotTask.dueAt == null,
      repeatRule: snapshotTask.repeatRule,
      clearRepeatRule: snapshotTask.repeatRule == null,
      dependencies: snapshotTask.dependencies,
      subtasksAutoFinish: snapshotTask.subtasksAutoFinish,
      subtasks: snapshotTask.subtasks,
      modifiedAt: nextModified,
    );

    final replacedTasks = <TaskItem>[
      for (final item in currentBoard.allTasks)
        item.id == snapshotTask.id ? restoredTask : item,
    ];
    final rearmedTasks = _rearmDependents(
      replacedTasks,
      entry.previouslyBlockedDependentIds,
      snapshotTask.id,
      restoredCompletions,
      now,
    );
    if (rearmedTasks == null) {
      _logSkipped(entry, 'timestamp_out_of_bounds');
      return null;
    }
    if (_hasDependencyCycle(rearmedTasks)) {
      _logSkipped(entry, 'dependency_cycle');
      return null;
    }

    final nextQueue = _restoreQueueMembership(
      currentBoard.queueBlock,
      entry,
      evictedByScopedDeletion: evictedByScopedDeletion,
      now: now,
    );
    if (nextQueue == null) {
      _logSkipped(entry, 'queue_limit_exceeded');
      return null;
    }
    if (_exceedsBlockLimit(
      tasks: rearmedTasks,
      labels: currentBoard.labels,
      locations: currentBoard.locations,
      deletedBlock: currentBoard.deletedBlock,
      queueBlock: nextQueue,
    )) {
      _logSkipped(entry, 'block_limit_exceeded');
      return null;
    }

    final evaluated = TaskBoard.evaluate(
      tasks: rearmedTasks,
      evaluationTime: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      labels: currentBoard.labels,
      locations: currentBoard.locations,
      deletedBlock: currentBoard.deletedBlock,
      queueBlock: nextQueue,
      pruneExpiredCompleted: false,
    );
    return TaskUndoOutcome(board: evaluated);
  }

  /// Reverses a task deletion on [currentBoard] via TDF `Undelete` semantics.
  static TaskUndoOutcome? _applyDelete(
    TaskBoard currentBoard,
    TaskUndoEntry entry,
    DateTime now,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  ) {
    final snapshotTask = entry.snapshotTask;
    final taskId = snapshotTask.id;
    if (currentBoard.findTask(taskId) != null) {
      _logSkipped(entry, 'task_already_live');
      return null;
    }

    final deletedRecord = currentBoard.deletedBlock.findTaskRecord(taskId);
    if (deletedRecord != null &&
        currentBoard.deletedBlock.generation >= TdfDeletedBlock.maxGeneration) {
      _logSkipped(entry, 'generation_limit_exceeded');
      return null;
    }

    final validLabelIds = <String>{
      for (final label in currentBoard.labels) label.id,
    };
    final validLocationIds = <String>{
      for (final location in currentBoard.locations) location.id,
    };
    final labelsWithLocation = _collectLabelsWithLocationRules(
      currentBoard.labels,
      validLocationIds,
    );
    final retainedLabels = <String>[
      for (final labelId in snapshotTask.labelIds)
        if (validLabelIds.contains(labelId)) labelId,
    ];
    final evictedByScopedDeletion =
        entry.hadOnlyScopedLabels && retainedLabels.isEmpty;
    final sanitizedConditions = _sanitizeConditions(
      snapshotTask.conditions,
      retainedLabels,
      validLocationIds,
      labelsWithLocation,
    );

    final decisionRevision = _computeDecisionRevision(
      now,
      snapshotTask.effectiveModifiedAt,
      deletedRecord?.deletedAt,
    );
    if (decisionRevision == null) {
      _logSkipped(entry, 'timestamp_out_of_bounds');
      return null;
    }

    final restoredCompletions = math.max(
      snapshotTask.completions,
      deletedRecord?.completionsCheckpoint ?? 0,
    );
    final wasCompleted =
        snapshotTask.isCompleted || snapshotTask.completedAt != null;
    final restoredTask = snapshotTask.copyWith(
      completions: restoredCompletions,
      isPriority: wasCompleted || evictedByScopedDeletion
          ? false
          : snapshotTask.isPriority,
      labelIds: retainedLabels,
      conditions: sanitizedConditions,
      modifiedAt: decisionRevision,
    );

    final nextQueue = wasCompleted
        ? _removeTaskFromQueueIfPresent(currentBoard.queueBlock, taskId, now)
        : _restoreQueueMembership(
            currentBoard.queueBlock,
            entry,
            evictedByScopedDeletion: evictedByScopedDeletion,
            now: now,
          );
    if (nextQueue == null) {
      _logSkipped(entry, 'queue_limit_exceeded');
      return null;
    }

    final nextDeletedBlock = deletedRecord == null
        ? currentBoard.deletedBlock
        : currentBoard.deletedBlock.copyWith(
            generation: currentBoard.deletedBlock.generation + 1,
            tasks: <TdfDeletedTaskRecord>[
              for (final record in currentBoard.deletedBlock.tasks)
                if (record.taskId != taskId) record,
            ],
          );

    final nextTasks = <TaskItem>[...currentBoard.allTasks, restoredTask];
    if (_exceedsBlockLimit(
      tasks: nextTasks,
      labels: currentBoard.labels,
      locations: currentBoard.locations,
      deletedBlock: nextDeletedBlock,
      queueBlock: nextQueue,
    )) {
      _logSkipped(entry, 'block_limit_exceeded');
      return null;
    }
    if (_hasDependencyCycle(nextTasks)) {
      _logSkipped(entry, 'dependency_cycle');
      return null;
    }

    final evaluated = TaskBoard.evaluate(
      tasks: nextTasks,
      evaluationTime: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      labels: currentBoard.labels,
      locations: currentBoard.locations,
      deletedBlock: nextDeletedBlock,
      queueBlock: nextQueue,
      pruneExpiredCompleted: false,
    );
    return TaskUndoOutcome(
      board: evaluated,
      taskConflictResolutions: <String, TdfDeletionResolution>{
        taskId: TdfDeletionResolution.undelete,
      },
    );
  }

  /// Reverses a step-down task downgrade on [currentBoard].
  static TaskUndoOutcome? _applyDowngrade(
    TaskBoard currentBoard,
    TaskUndoEntry entry,
    DateTime now,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  ) {
    final snapshotTask = entry.snapshotTask;
    final currentTask = currentBoard.findTask(snapshotTask.id);
    if (currentTask == null ||
        currentTask.isCompleted ||
        currentTask.completedAt != null) {
      _logSkipped(entry, 'task_not_open');
      return null;
    }

    final validLabelIds = <String>{
      for (final label in currentBoard.labels) label.id,
    };
    final validLocationIds = <String>{
      for (final location in currentBoard.locations) location.id,
    };
    final labelsWithLocation = _collectLabelsWithLocationRules(
      currentBoard.labels,
      validLocationIds,
    );
    final retainedLabels = <String>[
      for (final labelId in currentTask.labelIds)
        if (validLabelIds.contains(labelId)) labelId,
    ];
    final evictedByScopedDeletion =
        entry.hadOnlyScopedLabels && retainedLabels.isEmpty;
    final sanitizedConditions = _sanitizeConditions(
      currentTask.conditions,
      retainedLabels,
      validLocationIds,
      labelsWithLocation,
    );
    final targetPriority = evictedByScopedDeletion
        ? false
        : snapshotTask.isPriority;

    final nextQueue = _restoreQueueMembership(
      currentBoard.queueBlock,
      entry,
      evictedByScopedDeletion: evictedByScopedDeletion,
      now: now,
    );
    if (nextQueue == null) {
      _logSkipped(entry, 'queue_limit_exceeded');
      return null;
    }

    final taskChanged =
        currentTask.isPriority != targetPriority ||
        currentTask.suspendedAt != snapshotTask.suspendedAt ||
        currentTask.isSuspendedForever != snapshotTask.isSuspendedForever ||
        !listEquals(currentTask.labelIds, retainedLabels) ||
        !listEquals(currentTask.conditions, sanitizedConditions);
    final queueChanged = !listEquals(
      nextQueue.taskIds,
      currentBoard.queueBlock.taskIds,
    );
    if (!taskChanged && !queueChanged) {
      _logSkipped(entry, 'already_at_target_state');
      return null;
    }

    TaskItem replacementTask = currentTask;
    if (taskChanged) {
      final nextModified = _tryNextTimestamp(
        now,
        currentTask.effectiveModifiedAt,
      );
      if (nextModified == null) {
        _logSkipped(entry, 'timestamp_out_of_bounds');
        return null;
      }
      replacementTask = currentTask.copyWith(
        isPriority: targetPriority,
        labelIds: retainedLabels,
        conditions: sanitizedConditions,
        suspendedAt: snapshotTask.suspendedAt,
        clearSuspendedAt: snapshotTask.suspendedAt == null,
        isSuspendedForever: snapshotTask.isSuspendedForever,
        modifiedAt: nextModified,
      );
    }

    final nextTasks = taskChanged
        ? <TaskItem>[
            for (final item in currentBoard.allTasks)
              item.id == currentTask.id ? replacementTask : item,
          ]
        : currentBoard.allTasks;
    final evaluated = TaskBoard.evaluate(
      tasks: nextTasks,
      evaluationTime: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      labels: currentBoard.labels,
      locations: currentBoard.locations,
      deletedBlock: currentBoard.deletedBlock,
      queueBlock: nextQueue,
      pruneExpiredCompleted: false,
    );
    return TaskUndoOutcome(board: evaluated);
  }

  /// Collects the IDs of live [labels] that retain at least one live location rule in [validLocationIds].
  static Set<String> _collectLabelsWithLocationRules(
    List<TdfLabel> labels,
    Set<String> validLocationIds,
  ) => <String>{
    for (final label in labels)
      if (_hasLiveLocationRule(label.conditions, validLocationIds)) label.id,
  };

  /// Collects task IDs on [boardBefore] whose dependency on [taskBefore] was unsatisfied before completion.
  static Set<String> _collectPreviouslyBlockedDependents(
    TaskBoard boardBefore,
    TaskItem taskBefore,
  ) {
    final blockedIds = <String>{};
    for (final candidate in boardBefore.allTasks) {
      if (candidate.id != taskBefore.id &&
          _hasUnsatisfiedDependencyOn(
            candidate,
            taskBefore.id,
            taskBefore.completions,
          )) {
        blockedIds.add(candidate.id);
      }
    }
    return Set<String>.unmodifiable(blockedIds);
  }

  /// Computes `decisionRevision = max(now, max(liveRevision, deletedRevision) + 1s)` within TDF bounds.
  static DateTime? _computeDecisionRevision(
    DateTime now,
    DateTime liveRevision,
    DateTime? deletedRevision,
  ) {
    final maxObserved = _maxDateTime(liveRevision, deletedRevision);
    final bumped = TaskItem.normalizeTimestamp(maxObserved)
        .add(const Duration(seconds: 1));
    final decision = now.isAfter(bumped) ? now : bumped;
    return TdfCalendar.isWithinTimestampBounds(decision) ? decision : null;
  }

  /// Counts the canonical condition rules emitted by `TdfSerializer` for [conditions].
  static int _countSerializedConditionRules(List<TaskCondition> conditions) {
    if (conditions.isEmpty) return 0;
    if (conditions.any((rule) => rule is GlobalResetTaskCondition)) return 1;
    var nonIdLocationRules = 0;
    var hasLocationIds = false;
    var otherRules = 0;
    for (final rule in conditions) {
      if (rule is LocationTaskCondition) {
        if (rule.locationIds.isNotEmpty) {
          hasLocationIds = true;
        } else {
          nonIdLocationRules++;
        }
      } else if (rule.group != null) {
        otherRules++;
      }
    }
    return otherRules + nonIdLocationRules + (hasLocationIds ? 1 : 0);
  }

  /// Counts total `{ ... }` blocks emitted for [labels] (including multi-rule `condition` sub-blocks).
  static int _countSerializedLabelBlocks(List<TdfLabel> labels) {
    var total = 0;
    for (final label in labels) {
      total += 1;
      if (_countSerializedConditionRules(label.conditions) > 1) {
        total += 1;
      }
    }
    return total;
  }

  /// Counts total `{ ... }` blocks emitted for [tasks] (including `condition` and `subtasks` sub-blocks).
  static int _countSerializedTaskBlocks(List<TaskItem> tasks) {
    var total = 0;
    for (final task in tasks) {
      total += 1;
      if (_countSerializedConditionRules(task.conditions) > 1) {
        total += 1;
      }
      if (task.subtasks.isNotEmpty) {
        total += 1;
      }
    }
    return total;
  }

  /// Returns whether the candidate document exceeds [maxTdfBlocksPerDoc] (`4,096`) in merge or serializer bounds.
  static bool _exceedsBlockLimit({
    required List<TaskItem> tasks,
    required List<TdfLabel> labels,
    required List<TdfLocation> locations,
    required TdfDeletedBlock deletedBlock,
    required TdfQueueBlock queueBlock,
  }) {
    if (tasks.length + labels.length + locations.length + 2 >
        maxTdfBlocksPerDoc) {
      return true;
    }
    final metadataBlocks =
        (deletedBlock.isDefaultEmpty ? 0 : 1) +
        (queueBlock.isDefaultEmpty ? 0 : 1);
    final totalBlocks =
        metadataBlocks +
        locations.length +
        _countSerializedLabelBlocks(labels) +
        _countSerializedTaskBlocks(tasks);
    return totalBlocks > maxTdfBlocksPerDoc;
  }

  /// Computes the target insertion index in [withoutTask] from [queueOrderSnapshot] in $O(N)$ time.
  static int _findInsertionIndex(
    List<String> withoutTask,
    List<String> queueOrderSnapshot,
    int snapshotIndex,
  ) {
    if (snapshotIndex < 0) return withoutTask.length;
    final currentPositions = <String, int>{
      for (var i = 0; i < withoutTask.length; i++) withoutTask[i]: i,
    };
    for (var i = snapshotIndex - 1; i >= 0; i--) {
      if (currentPositions[queueOrderSnapshot[i]] case final predecessorIdx?) {
        return predecessorIdx + 1;
      }
    }
    for (var i = snapshotIndex + 1; i < queueOrderSnapshot.length; i++) {
      if (currentPositions[queueOrderSnapshot[i]] case final successorIdx?) {
        return successorIdx;
      }
    }
    return snapshotIndex == 0 ? 0 : withoutTask.length;
  }

  /// Returns whether [tasks] contains any directed dependency cycle.
  static bool _hasDependencyCycle(List<TaskItem> tasks) {
    final taskMap = <String, TaskItem>{for (final task in tasks) task.id: task};
    final visitState = <String, int>{};
    for (final id in taskMap.keys) {
      if ((visitState[id] ?? 0) == 0 &&
          _visitCycleDfs(id, taskMap, visitState)) {
        return true;
      }
    }
    return false;
  }

  /// Returns whether [conditions] contains a `LocationTaskCondition` referencing [validLocationIds] or legacy coordinates.
  static bool _hasLiveLocationRule(
    List<TaskCondition> conditions,
    Set<String> validLocationIds,
  ) {
    for (final rule in conditions) {
      if (rule is LocationTaskCondition &&
          (rule.locationIds.any(validLocationIds.contains) ||
              (rule.locationIds.isEmpty && rule.radiusMeters > 0))) {
        return true;
      }
    }
    return false;
  }

  /// Returns whether [candidate] has an unsatisfied dependency on [blockerId] at [blockerCompletions].
  static bool _hasUnsatisfiedDependencyOn(
    TaskItem candidate,
    String blockerId,
    int blockerCompletions,
  ) {
    for (final dependency in candidate.dependencies) {
      if (dependency.taskId == blockerId &&
          blockerCompletions < dependency.requiredCompletion) {
        return true;
      }
    }
    return false;
  }

  /// Emits a structured `task.undo.skipped` diagnostic event with [reason].
  static void _logSkipped(TaskUndoEntry entry, String reason) {
    if (!AppLogger.shouldLog(LogLevel.info)) return;
    AppLogger.event(
      LogLevel.info,
      LogTag.domain,
      'task.undo.skipped',
      fields: <String, Object?>{
        'id': entry.snapshotTask.id,
        'kind': entry.kind.name,
        'seq': entry.sequence,
        'reason': reason,
      },
    );
  }

  /// Returns the later of [left] and optional [right].
  static DateTime _maxDateTime(DateTime left, DateTime? right) =>
      right != null && right.isAfter(left) ? right : left;

  /// Re-arms [candidate]'s dependency on [blockerId] to `restoredCompletions + 1` when previously blocked.
  static TaskItem? _rearmDependentIfNeeded(
    TaskItem candidate,
    String blockerId,
    int restoredCompletions,
    DateTime now,
  ) {
    if (restoredCompletions >= TdfTaskDependency.maxCompletions) {
      return candidate;
    }
    var changed = false;
    final updatedDependencies = <TdfTaskDependency>[];
    for (final dependency in candidate.dependencies) {
      if (dependency.taskId == blockerId &&
          dependency.requiredCompletion <= restoredCompletions) {
        updatedDependencies.add(
          TdfTaskDependency(
            taskId: blockerId,
            requiredCompletion: restoredCompletions + 1,
          ),
        );
        changed = true;
      } else {
        updatedDependencies.add(dependency);
      }
    }
    if (!changed) return candidate;
    final nextModified = _tryNextTimestamp(now, candidate.effectiveModifiedAt);
    if (nextModified == null) return null;
    return candidate.copyWith(
      dependencies: updatedDependencies,
      modifiedAt: nextModified,
    );
  }

  /// Re-arms every live task in [previouslyBlockedIds] whose dependency on [blockerId] was satisfied by completion.
  static List<TaskItem>? _rearmDependents(
    List<TaskItem> tasks,
    Set<String> previouslyBlockedIds,
    String blockerId,
    int restoredCompletions,
    DateTime now,
  ) {
    if (previouslyBlockedIds.isEmpty) return tasks;
    final updated = <TaskItem>[];
    for (final task in tasks) {
      if (!previouslyBlockedIds.contains(task.id) || task.id == blockerId) {
        updated.add(task);
        continue;
      }
      final rearmed = _rearmDependentIfNeeded(
        task,
        blockerId,
        restoredCompletions,
        now,
      );
      if (rearmed == null) return null;
      updated.add(rearmed);
    }
    return updated;
  }

  /// Removes [taskId] from [currentQueue] if present, advancing `modifiedAt` when removed.
  static TdfQueueBlock? _removeTaskFromQueueIfPresent(
    TdfQueueBlock currentQueue,
    String taskId,
    DateTime now,
  ) {
    if (!currentQueue.taskIds.contains(taskId)) return currentQueue;
    final nextModified = _tryNextTimestamp(now, currentQueue.modifiedAt);
    if (nextModified == null) return null;
    return TdfQueueBlock(
      modifiedAt: nextModified,
      taskIds: <String>[
        for (final id in currentQueue.taskIds)
          if (id != taskId) id,
      ],
    );
  }

  /// Reconstructs [entry]'s relative membership and position in [currentQueue], or returns `null` if limits are exceeded.
  static TdfQueueBlock? _restoreQueueMembership(
    TdfQueueBlock currentQueue,
    TaskUndoEntry entry, {
    required bool evictedByScopedDeletion,
    required DateTime now,
  }) {
    final taskId = entry.snapshotTask.id;
    if (!entry.wasQueued || evictedByScopedDeletion) {
      return _removeTaskFromQueueIfPresent(currentQueue, taskId, now);
    }

    final withoutTask = <String>[
      for (final id in currentQueue.taskIds)
        if (id != taskId) id,
    ];
    if (withoutTask.length >= TdfQueueBlock.maxQueueEntries) {
      return null;
    }
    final snapshotIndex = entry.queueOrderSnapshot.indexOf(taskId);
    final insertIndex = _findInsertionIndex(
      withoutTask,
      entry.queueOrderSnapshot,
      snapshotIndex,
    );
    final nextIds = <String>[
      ...withoutTask.sublist(0, insertIndex),
      taskId,
      ...withoutTask.sublist(insertIndex),
    ];
    if (listEquals(nextIds, currentQueue.taskIds)) return currentQueue;
    final nextModified = _tryNextTimestamp(now, currentQueue.modifiedAt);
    if (nextModified == null) return null;
    return TdfQueueBlock(modifiedAt: nextModified, taskIds: nextIds);
  }

  /// Sanitizes [conditions] against [validLocationIds], inserting `condition location any` when an inherited location rule in [labelsWithLocationRules] was previously overridden.
  static List<TaskCondition> _sanitizeConditions(
    List<TaskCondition> conditions,
    List<String> retainedLabelIds,
    Set<String> validLocationIds,
    Set<String> labelsWithLocationRules,
  ) {
    if (conditions.isEmpty) return conditions;
    final hasInheritedLocationRule = retainedLabelIds.any(
      labelsWithLocationRules.contains,
    );
    final sanitized = <TaskCondition>[];
    for (final rule in conditions) {
      _sanitizeSingleConditionRule(
        rule,
        hasInheritedLocationRule,
        validLocationIds,
        sanitized,
      );
    }
    return listEquals(sanitized, conditions) ? conditions : sanitized;
  }

  /// Filters a single [rule] against [validLocationIds] and appends surviving or reset rules to [output].
  static void _sanitizeSingleConditionRule(
    TaskCondition rule,
    bool hasInheritedLocationRule,
    Set<String> validLocationIds,
    List<TaskCondition> output,
  ) {
    if (rule is! LocationTaskCondition || rule.locationIds.isEmpty) {
      output.add(rule);
      return;
    }
    final retainedIds = <String>[
      for (final id in rule.locationIds)
        if (validLocationIds.contains(id)) id,
    ];
    if (retainedIds.isNotEmpty) {
      output.add(LocationTaskCondition.fromIds(retainedIds));
      return;
    }
    const locationReset = GroupResetTaskCondition(
      targetGroup: ConditionGroup.location,
    );
    if (hasInheritedLocationRule && !output.contains(locationReset)) {
      output.add(locationReset);
    }
  }

  /// Computes `TaskItem.nextModifiedTimestamp(now, previous)` without throwing when `9999-12-31 23:59:59` is exceeded.
  static DateTime? _tryNextTimestamp(DateTime now, DateTime? previous) {
    try {
      return TaskItem.nextModifiedTimestamp(now, previous);
    } on FormatException {
      return null;
    }
  }

  /// Visits [taskId] during 3-color cycle detection (`0 = unvisited`, `1 = visiting`, `2 = visited`).
  static bool _visitCycleDfs(
    String taskId,
    Map<String, TaskItem> taskMap,
    Map<String, int> visitState,
  ) {
    visitState[taskId] = 1;
    final task = taskMap[taskId];
    if (task != null) {
      for (final dependency in task.dependencies) {
        final nextState = visitState[dependency.taskId] ?? 0;
        if (nextState == 1) return true;
        if (nextState == 0 &&
            taskMap.containsKey(dependency.taskId) &&
            _visitCycleDfs(dependency.taskId, taskMap, visitState)) {
          return true;
        }
      }
    }
    visitState[taskId] = 2;
    return false;
  }
}

/// Immutable snapshot of a single undoable task mutation.
@immutable
class TaskUndoEntry {
  /// Creates a [TaskUndoEntry].
  const TaskUndoEntry({
    required this.sequence,
    required this.kind,
    required this.snapshotTask,
    required this.wasQueued,
    required this.queueOrderSnapshot,
    required this.hadOnlyScopedLabels,
    this.previouslyBlockedDependentIds = const <String>{},
  });

  /// Whether [snapshotTask] was restricted from the global view by scoped-only labels before the mutation.
  final bool hadOnlyScopedLabels;

  /// Action category recorded by this entry.
  final TaskUndoActionKind kind;

  /// Task IDs whose dependency on `snapshotTask.id` was unsatisfied immediately before completion.
  final Set<String> previouslyBlockedDependentIds;

  /// Unmodifiable `queueBlock.taskIds` order from the board immediately before the mutation.
  final List<String> queueOrderSnapshot;

  /// Monotonically increasing session sequence number identifying this entry.
  final int sequence;

  /// Immutable pre-mutation [TaskItem] snapshot.
  final TaskItem snapshotTask;

  /// Whether `snapshotTask.id` was present in `queueBlock.taskIds` before the mutation.
  final bool wasQueued;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TaskUndoEntry &&
        other.sequence == sequence &&
        other.kind == kind &&
        other.snapshotTask == snapshotTask &&
        other.wasQueued == wasQueued &&
        other.hadOnlyScopedLabels == hadOnlyScopedLabels &&
        listEquals(other.queueOrderSnapshot, queueOrderSnapshot) &&
        setEquals(
          other.previouslyBlockedDependentIds,
          previouslyBlockedDependentIds,
        );
  }

  @override
  int get hashCode => Object.hash(
    sequence,
    kind,
    snapshotTask,
    wasQueued,
    hadOnlyScopedLabels,
    Object.hashAll(queueOrderSnapshot),
    Object.hashAllUnordered(previouslyBlockedDependentIds),
  );
}

/// Result of applying a [TaskUndoEntry] onto the current [TaskBoard].
@immutable
class TaskUndoOutcome {
  /// Creates a [TaskUndoOutcome].
  const TaskUndoOutcome({
    required this.board,
    this.taskConflictResolutions = const <String, TdfDeletionResolution>{},
  });

  /// Re-evaluated [TaskBoard] produced by the undo transition.
  final TaskBoard board;

  /// Per-task deletion conflict resolutions forwarded to synchronization.
  final Map<String, TdfDeletionResolution> taskConflictResolutions;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TaskUndoOutcome &&
        other.board == board &&
        mapEquals(other.taskConflictResolutions, taskConflictResolutions);
  }

  @override
  int get hashCode => Object.hash(
    board,
    Object.hashAllUnordered(
      taskConflictResolutions.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
  );
}
