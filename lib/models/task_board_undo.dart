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
/// while preserving TDF `0.7.0` monotonic completion, revision, queue, metadata
/// ownership, and deletion-generation invariants.
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
    Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
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
        dueLeadWindow,
      ),
      TaskUndoActionKind.downgrade => _applyDowngrade(
        currentBoard,
        entry,
        now,
        localEvaluationTime,
        timeZone,
        dueLeadWindow,
      ),
      TaskUndoActionKind.delete => _applyDelete(
        currentBoard,
        entry,
        now,
        localEvaluationTime,
        timeZone,
        dueLeadWindow,
      ),
    };
  }

  /// Captures a pre-mutation [TaskUndoEntry] from [boardBefore], [taskBefore],
  /// and optional [boardAfter] or explicit [previouslyBlockedDependencies].
  static TaskUndoEntry capture({
    required int sequence,
    required TaskUndoActionKind kind,
    required TaskBoard boardBefore,
    required TaskItem taskBefore,
    TaskBoard? boardAfter,
    Map<String, TdfTaskDependency>? previouslyBlockedDependencies,
  }) {
    final labelMap = <String, TdfLabel>{
      for (final label in boardBefore.labels) label.id: label,
    };
    final blockedDependents = kind == TaskUndoActionKind.complete
        ? _collectPreviouslyBlockedDependents(boardBefore, taskBefore)
        : const <String>{};
    final strippedDependencies =
        previouslyBlockedDependencies ??
        (boardAfter != null
            ? TaskUndoEntry.captureStrippedDependencies(
                boardBefore: boardBefore,
                boardAfter: boardAfter,
                targetTaskId: taskBefore.id,
              )
            : _predictStrippedDependencies(kind, boardBefore, taskBefore));
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
      previouslyBlockedDependencies: strippedDependencies,
    );
  }

  /// Reverses a direct or `subtasks auto-finish` task completion on [currentBoard].
  static TaskUndoOutcome? _applyComplete(
    TaskBoard currentBoard,
    TaskUndoEntry entry,
    DateTime now,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow,
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
    final deletedTaskIds = <String>{
      for (final record in currentBoard.deletedBlock.tasks) record.taskId,
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
    final deferral = _resolveRestoredDeferral(
      snapshotTask,
      now,
      stripAll: false,
    );
    final restoredTask = currentTask.copyWith(
      isCompleted: false,
      clearCompletedAt: true,
      completions: restoredCompletions,
      isPriority: evictedByScopedDeletion ? false : snapshotTask.isPriority,
      labelIds: retainedLabels,
      conditions: sanitizedConditions,
      suspendedAt: deferral.suspendedAt,
      clearSuspendedAt: deferral.suspendedAt == null,
      isSuspendedForever: deferral.isSuspendedForever,
      suspendedNote: deferral.suspendedNote,
      clearSuspendedNote: deferral.suspendedNote == null,
      dueAt: snapshotTask.dueAt,
      clearDueAt: snapshotTask.dueAt == null,
      isDuePassive: snapshotTask.isDuePassive,
      dueNote: snapshotTask.dueNote,
      clearDueNote: snapshotTask.dueNote == null,
      repeatRule: snapshotTask.repeatRule,
      clearRepeatRule: snapshotTask.repeatRule == null,
      dependencies: _filterDeletedDependencies(
        snapshotTask.dependencies,
        deletedTaskIds,
      ),
      history: snapshotTask.history,
      subtasksAutoFinish: snapshotTask.subtasksAutoFinish,
      subtasks: snapshotTask.subtasks,
      modifiedAt: nextModified,
    );

    final replacedTasks = <TaskItem>[
      for (final item in currentBoard.allTasks)
        item.id == snapshotTask.id ? restoredTask : item,
    ];
    final rearmedTasks = _restoreAndRearmDependents(
      replacedTasks,
      entry,
      restoredTargetIsOpen: true,
      restoredCompletions: restoredCompletions,
      now: now,
    );
    if (rearmedTasks == null) {
      return null;
    }
    if (!_checkTaskAndLabelBounds(entry, rearmedTasks, currentBoard.labels)) {
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
      dueLeadWindow: dueLeadWindow,
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
    Duration? dueLeadWindow,
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
    final nextDeletedBlock = deletedRecord == null
        ? currentBoard.deletedBlock
        : currentBoard.deletedBlock.copyWith(
            generation: currentBoard.deletedBlock.generation + 1,
            tasks: <TdfDeletedTaskRecord>[
              for (final record in currentBoard.deletedBlock.tasks)
                if (record.taskId != taskId) record,
            ],
          );
    final deletedTaskIds = <String>{
      for (final record in nextDeletedBlock.tasks) record.taskId,
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
    final deferral = _resolveRestoredDeferral(
      snapshotTask,
      now,
      stripAll: wasCompleted,
    );
    final restoredTask = snapshotTask.copyWith(
      completions: restoredCompletions,
      isPriority: wasCompleted || evictedByScopedDeletion
          ? false
          : snapshotTask.isPriority,
      labelIds: retainedLabels,
      conditions: sanitizedConditions,
      suspendedAt: deferral.suspendedAt,
      clearSuspendedAt: deferral.suspendedAt == null,
      isSuspendedForever: deferral.isSuspendedForever,
      suspendedNote: deferral.suspendedNote,
      clearSuspendedNote: deferral.suspendedNote == null,
      dueAt: snapshotTask.dueAt,
      clearDueAt: snapshotTask.dueAt == null,
      isDuePassive: wasCompleted ? false : snapshotTask.isDuePassive,
      dueNote: snapshotTask.dueNote,
      clearDueNote: snapshotTask.dueNote == null,
      dependencies: wasCompleted
          ? const <TdfTaskDependency>[]
          : _filterDeletedDependencies(
              snapshotTask.dependencies,
              deletedTaskIds,
            ),
      history: snapshotTask.history,
      modifiedAt: decisionRevision,
    );

    final candidateTasks = <TaskItem>[...currentBoard.allTasks, restoredTask];
    final nextTasks = _restoreAndRearmDependents(
      candidateTasks,
      entry,
      restoredTargetIsOpen: !wasCompleted,
      restoredCompletions: restoredCompletions,
      now: now,
    );
    if (nextTasks == null) {
      return null;
    }
    if (!_checkTaskAndLabelBounds(entry, nextTasks, currentBoard.labels)) {
      return null;
    }
    if (_hasDependencyCycle(nextTasks)) {
      _logSkipped(entry, 'dependency_cycle');
      return null;
    }

    final nextQueue = wasCompleted
        ? _removeTaskFromQueueIfPresent(
            currentBoard.queueBlock,
            taskId,
            now,
            entry,
          )
        : _restoreQueueMembership(
            currentBoard.queueBlock,
            entry,
            evictedByScopedDeletion: evictedByScopedDeletion,
            now: now,
          );
    if (nextQueue == null) {
      return null;
    }

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

    final evaluated = TaskBoard.evaluate(
      tasks: nextTasks,
      evaluationTime: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
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
    Duration? dueLeadWindow,
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
    final deferral = _resolveRestoredDeferral(
      snapshotTask,
      now,
      stripAll: false,
    );

    final nextQueue = _restoreQueueMembership(
      currentBoard.queueBlock,
      entry,
      evictedByScopedDeletion: evictedByScopedDeletion,
      now: now,
    );
    if (nextQueue == null) {
      return null;
    }

    final taskChanged =
        currentTask.isPriority != targetPriority ||
        currentTask.suspendedAt != deferral.suspendedAt ||
        currentTask.isSuspendedForever != deferral.isSuspendedForever ||
        currentTask.suspendedNote != deferral.suspendedNote ||
        currentTask.dueAt != snapshotTask.dueAt ||
        currentTask.isDuePassive != snapshotTask.isDuePassive ||
        currentTask.dueNote != snapshotTask.dueNote ||
        !listEquals(currentTask.history, snapshotTask.history) ||
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
        suspendedAt: deferral.suspendedAt,
        clearSuspendedAt: deferral.suspendedAt == null,
        isSuspendedForever: deferral.isSuspendedForever,
        suspendedNote: deferral.suspendedNote,
        clearSuspendedNote: deferral.suspendedNote == null,
        dueAt: snapshotTask.dueAt,
        clearDueAt: snapshotTask.dueAt == null,
        isDuePassive: snapshotTask.isDuePassive,
        dueNote: snapshotTask.dueNote,
        clearDueNote: snapshotTask.dueNote == null,
        history: snapshotTask.history,
        modifiedAt: nextModified,
      );
    }

    final nextTasks = taskChanged
        ? <TaskItem>[
            for (final item in currentBoard.allTasks)
              item.id == currentTask.id ? replacementTask : item,
          ]
        : currentBoard.allTasks;
    if (!_checkTaskAndLabelBounds(entry, nextTasks, currentBoard.labels)) {
      return null;
    }
    if (_exceedsBlockLimit(
      tasks: nextTasks,
      labels: currentBoard.labels,
      locations: currentBoard.locations,
      deletedBlock: currentBoard.deletedBlock,
      queueBlock: nextQueue,
    )) {
      _logSkipped(entry, 'block_limit_exceeded');
      return null;
    }

    final evaluated = TaskBoard.evaluate(
      tasks: nextTasks,
      evaluationTime: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
      labels: currentBoard.labels,
      locations: currentBoard.locations,
      deletedBlock: currentBoard.deletedBlock,
      queueBlock: nextQueue,
      pruneExpiredCompleted: false,
    );
    return TaskUndoOutcome(board: evaluated);
  }

  /// Validates per-argument dependency bounds (`64`) and per-block statement bounds (`1,024`).
  static bool _checkTaskAndLabelBounds(
    TaskUndoEntry entry,
    List<TaskItem> tasks,
    List<TdfLabel> labels,
  ) {
    for (final label in labels) {
      if (label.canonicalDirectChildStatementCount > maxTdfStmtsPerBlock ||
          _countSerializedConditionRules(label.conditions) >
              maxTdfStmtsPerBlock) {
        _logSkipped(entry, 'statement_limit_exceeded');
        return false;
      }
    }
    for (final task in tasks) {
      if (task.dependencies.length > maxTdfArgsPerStmt) {
        _logSkipped(entry, 'dependency_limit_exceeded');
        return false;
      }
      if (task.canonicalDirectChildStatementCount > maxTdfStmtsPerBlock ||
          task.subtasks.length > maxTdfStmtsPerBlock ||
          _countSerializedConditionRules(task.conditions) >
              maxTdfStmtsPerBlock) {
        _logSkipped(entry, 'statement_limit_exceeded');
        return false;
      }
    }
    return true;
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

  /// Removes dependencies referencing tombstoned task IDs in [deletedTaskIds].
  static List<TdfTaskDependency> _filterDeletedDependencies(
    List<TdfTaskDependency> dependencies,
    Set<String> deletedTaskIds,
  ) {
    if (dependencies.isEmpty || deletedTaskIds.isEmpty) {
      return dependencies;
    }
    final filtered = <TdfTaskDependency>[
      for (final dependency in dependencies)
        if (!deletedTaskIds.contains(dependency.taskId)) dependency,
    ];
    return filtered.length == dependencies.length ? dependencies : filtered;
  }

  /// Returns the normalized [TdfTaskDependency] on [task] targeting [targetTaskId], if present.
  static TdfTaskDependency? _findDependencyTargeting(
    TaskItem task,
    String targetTaskId,
  ) {
    for (final dependency in task.dependencies) {
      if (dependency.taskId == targetTaskId) {
        return dependency;
      }
    }
    return null;
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

  /// Predicts whether [candidate]'s dependency on [taskBefore] is stripped by [kind].
  static TdfTaskDependency? _predictSingleStrippedDependency(
    TaskUndoActionKind kind,
    TaskItem candidate,
    TaskItem taskBefore,
  ) {
    if (candidate.id == taskBefore.id ||
        candidate.isCompleted ||
        candidate.completedAt != null) {
      return null;
    }
    final dependency = _findDependencyTargeting(candidate, taskBefore.id);
    if (dependency == null) return null;
    if (kind == TaskUndoActionKind.delete) {
      return dependency;
    }
    final nextCompletions = taskBefore.completions + 1;
    final nonRecurringPair =
        candidate.repeatRule == null || taskBefore.repeatRule == null;
    if (nonRecurringPair && nextCompletions >= dependency.requiredCompletion) {
      return dependency;
    }
    return null;
  }

  /// Predicts dependencies stripped from open dependents when `boardAfter` is omitted at capture time.
  static Map<String, TdfTaskDependency> _predictStrippedDependencies(
    TaskUndoActionKind kind,
    TaskBoard boardBefore,
    TaskItem taskBefore,
  ) {
    if (kind == TaskUndoActionKind.downgrade) {
      return const <String, TdfTaskDependency>{};
    }
    final captured = <String, TdfTaskDependency>{};
    for (final candidate in boardBefore.allTasks) {
      final dependency = _predictSingleStrippedDependency(
        kind,
        candidate,
        taskBefore,
      );
      if (dependency != null) {
        captured[candidate.id] = dependency;
      }
    }
    return captured.isEmpty
        ? const <String, TdfTaskDependency>{}
        : Map<String, TdfTaskDependency>.unmodifiable(captured);
  }

  /// Re-arms an existing live dependency on [candidate] targeting `entry.snapshotTask.id` to `restoredCompletions + 1`.
  static TaskItem? _rearmExistingDependent(
    TaskItem candidate,
    TdfTaskDependency existingDependency,
    TaskUndoEntry entry,
    int restoredCompletions,
    DateTime now,
  ) {
    if (existingDependency.requiredCompletion > restoredCompletions) {
      return candidate;
    }
    if (restoredCompletions >= TdfTaskDependency.maxCompletions) {
      _logSkipped(entry, 'completions_limit_exceeded');
      return null;
    }
    final nextModified = _tryNextTimestamp(now, candidate.effectiveModifiedAt);
    if (nextModified == null) {
      _logSkipped(entry, 'timestamp_out_of_bounds');
      return null;
    }
    final updatedDependencies = <TdfTaskDependency>[
      for (final dependency in candidate.dependencies)
        dependency.taskId == entry.snapshotTask.id
            ? TdfTaskDependency(
                taskId: entry.snapshotTask.id,
                requiredCompletion: restoredCompletions + 1,
              )
            : dependency,
    ];
    return candidate.copyWith(
      dependencies: updatedDependencies,
      modifiedAt: nextModified,
    );
  }

  /// Re-inserts [capturedDependency] onto open [candidate], re-arming when previously unsatisfied.
  static TaskItem? _reinsertStrippedDependency(
    TaskItem candidate,
    TdfTaskDependency capturedDependency,
    TaskUndoEntry entry, {
    required bool restoredTargetIsOpen,
    required int restoredCompletions,
    required DateTime now,
  }) {
    if (candidate.dependencies.length >= maxTdfArgsPerStmt) {
      _logSkipped(entry, 'dependency_limit_exceeded');
      return null;
    }
    final needsRearm =
        restoredTargetIsOpen &&
        entry.snapshotTask.completions <
            capturedDependency.requiredCompletion &&
        capturedDependency.requiredCompletion <= restoredCompletions;
    if (needsRearm && restoredCompletions >= TdfTaskDependency.maxCompletions) {
      _logSkipped(entry, 'completions_limit_exceeded');
      return null;
    }
    final nextModified = _tryNextTimestamp(now, candidate.effectiveModifiedAt);
    if (nextModified == null) {
      _logSkipped(entry, 'timestamp_out_of_bounds');
      return null;
    }
    final restoredDependency = needsRearm
        ? TdfTaskDependency(
            taskId: entry.snapshotTask.id,
            requiredCompletion: restoredCompletions + 1,
          )
        : capturedDependency;
    return candidate.copyWith(
      dependencies: TdfTaskDependency.normalizeList(<TdfTaskDependency>[
        ...candidate.dependencies,
        restoredDependency,
      ]),
      modifiedAt: nextModified,
    );
  }

  /// Removes [taskId] from [currentQueue] if present, advancing `modifiedAt` when removed.
  static TdfQueueBlock? _removeTaskFromQueueIfPresent(
    TdfQueueBlock currentQueue,
    String taskId,
    DateTime now,
    TaskUndoEntry entry,
  ) {
    if (!currentQueue.taskIds.contains(taskId)) return currentQueue;
    final nextModified = _tryNextTimestamp(now, currentQueue.modifiedAt);
    if (nextModified == null) {
      _logSkipped(entry, 'timestamp_out_of_bounds');
      return null;
    }
    return TdfQueueBlock(
      modifiedAt: nextModified,
      taskIds: <String>[
        for (final id in currentQueue.taskIds)
          if (id != taskId) id,
      ],
    );
  }

  /// Resolves the restored deferral tuple for [snapshotTask] at [now], stripping expired finite deferrals with their note.
  static _RestoredDeferral _resolveRestoredDeferral(
    TaskItem snapshotTask,
    DateTime now, {
    required bool stripAll,
  }) {
    if (stripAll) {
      return (
        isSuspendedForever: false,
        suspendedAt: null,
        suspendedNote: null,
      );
    }
    if (snapshotTask.isSuspendedForever) {
      return (
        isSuspendedForever: true,
        suspendedAt: null,
        suspendedNote: snapshotTask.suspendedNote,
      );
    }
    if (snapshotTask.suspendedAt case final suspendedAt?
        when suspendedAt.isAfter(now)) {
      return (
        isSuspendedForever: false,
        suspendedAt: suspendedAt,
        suspendedNote: snapshotTask.suspendedNote,
      );
    }
    return (isSuspendedForever: false, suspendedAt: null, suspendedNote: null);
  }

  /// Restores stripped dependencies and re-arms unsatisfied open dependents across [tasks], aborting atomically on any bound violation.
  static List<TaskItem>? _restoreAndRearmDependents(
    List<TaskItem> tasks,
    TaskUndoEntry entry, {
    required bool restoredTargetIsOpen,
    required int restoredCompletions,
    required DateTime now,
  }) {
    if (entry.previouslyBlockedDependencies.isEmpty &&
        entry.previouslyBlockedDependentIds.isEmpty) {
      return tasks;
    }
    final updated = <TaskItem>[];
    for (final candidate in tasks) {
      final nextTask = _restoreAndRearmSingleDependent(
        candidate,
        entry,
        restoredTargetIsOpen: restoredTargetIsOpen,
        restoredCompletions: restoredCompletions,
        now: now,
      );
      if (nextTask == null) return null;
      updated.add(nextTask);
    }
    return updated;
  }

  /// Restores or re-arms a single surviving open [candidate] dependent, or returns `null` when a bound guard fails.
  static TaskItem? _restoreAndRearmSingleDependent(
    TaskItem candidate,
    TaskUndoEntry entry, {
    required bool restoredTargetIsOpen,
    required int restoredCompletions,
    required DateTime now,
  }) {
    final targetId = entry.snapshotTask.id;
    if (candidate.id == targetId ||
        candidate.isCompleted ||
        candidate.completedAt != null) {
      return candidate;
    }
    final existingDependency = _findDependencyTargeting(candidate, targetId);
    if (existingDependency == null) {
      final captured = entry.previouslyBlockedDependencies[candidate.id];
      if (captured == null) return candidate;
      return _reinsertStrippedDependency(
        candidate,
        captured,
        entry,
        restoredTargetIsOpen: restoredTargetIsOpen,
        restoredCompletions: restoredCompletions,
        now: now,
      );
    }
    if (entry.kind == TaskUndoActionKind.complete &&
        restoredTargetIsOpen &&
        entry.previouslyBlockedDependentIds.contains(candidate.id)) {
      return _rearmExistingDependent(
        candidate,
        existingDependency,
        entry,
        restoredCompletions,
        now,
      );
    }
    return candidate;
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
      return _removeTaskFromQueueIfPresent(currentQueue, taskId, now, entry);
    }

    final withoutTask = <String>[
      for (final id in currentQueue.taskIds)
        if (id != taskId) id,
    ];
    if (withoutTask.length >= TdfQueueBlock.maxQueueEntries) {
      _logSkipped(entry, 'queue_limit_exceeded');
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
    if (nextModified == null) {
      _logSkipped(entry, 'timestamp_out_of_bounds');
      return null;
    }
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
  /// Creates a [TaskUndoEntry] with unmodifiable collection snapshots.
  TaskUndoEntry({
    required this.sequence,
    required this.kind,
    required this.snapshotTask,
    required this.wasQueued,
    required List<String> queueOrderSnapshot,
    required this.hadOnlyScopedLabels,
    Set<String> previouslyBlockedDependentIds = const <String>{},
    Map<String, TdfTaskDependency> previouslyBlockedDependencies =
        const <String, TdfTaskDependency>{},
  }) : queueOrderSnapshot = List<String>.unmodifiable(queueOrderSnapshot),
       previouslyBlockedDependentIds = Set<String>.unmodifiable(
         previouslyBlockedDependentIds,
       ),
       previouslyBlockedDependencies =
           Map<String, TdfTaskDependency>.unmodifiable(
             previouslyBlockedDependencies,
           );

  /// Whether [snapshotTask] was restricted from the global view by scoped-only labels before the mutation.
  final bool hadOnlyScopedLabels;

  /// Action category recorded by this entry.
  final TaskUndoActionKind kind;

  /// Unmodifiable map of open dependent task IDs to their exact [TdfTaskDependency] on `snapshotTask.id` stripped during the action.
  final Map<String, TdfTaskDependency> previouslyBlockedDependencies;

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

  /// Captures exact [TdfTaskDependency] entries on open tasks in [boardBefore] targeting [targetTaskId] that were stripped on open tasks in [boardAfter].
  static Map<String, TdfTaskDependency> captureStrippedDependencies({
    required TaskBoard boardBefore,
    required TaskBoard boardAfter,
    required String targetTaskId,
  }) {
    final stripped = <String, TdfTaskDependency>{};
    for (final beforeTask in boardBefore.allTasks) {
      if (beforeTask.id == targetTaskId ||
          beforeTask.isCompleted ||
          beforeTask.completedAt != null) {
        continue;
      }
      final beforeDependency = _findTargetDependency(beforeTask, targetTaskId);
      if (beforeDependency == null) continue;
      final afterTask = boardAfter.findTask(beforeTask.id);
      if (afterTask == null ||
          afterTask.isCompleted ||
          afterTask.completedAt != null) {
        continue;
      }
      if (_findTargetDependency(afterTask, targetTaskId) == null) {
        stripped[beforeTask.id] = beforeDependency;
      }
    }
    return stripped.isEmpty
        ? const <String, TdfTaskDependency>{}
        : Map<String, TdfTaskDependency>.unmodifiable(stripped);
  }

  /// Finds the normalized [TdfTaskDependency] on [task] targeting [targetTaskId], if present.
  static TdfTaskDependency? _findTargetDependency(
    TaskItem task,
    String targetTaskId,
  ) {
    for (final dependency in task.dependencies) {
      if (dependency.taskId == targetTaskId) {
        return dependency;
      }
    }
    return null;
  }

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
        ) &&
        mapEquals(
          other.previouslyBlockedDependencies,
          previouslyBlockedDependencies,
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
    Object.hashAllUnordered(
      previouslyBlockedDependencies.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
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

/// Normalized deferral tuple restored onto a task snapshot during undo.
typedef _RestoredDeferral = ({
  bool isSuspendedForever,
  DateTime? suspendedAt,
  String? suspendedNote,
});
