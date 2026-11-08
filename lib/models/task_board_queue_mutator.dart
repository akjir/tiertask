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

import 'task_board_evaluator.dart';
import 'task_item.dart';
import 'task_tier.dart';
import 'tdf_sync_metadata.dart';
import 'tdf_timezone.dart';

/// Task lookup and tier slice indexing helpers on [NormalizedTierSlices].
extension TaskBoardQueueSlicesX on NormalizedTierSlices {
  /// Finds the [TaskItem] with [taskId], or `null` if not found.
  TaskItem? findTask(String taskId) {
    for (final tier in TaskTier.values) {
      if (_findInList(tasksForTier(tier), taskId) case final found?) {
        return found;
      }
    }
    return _findInList(scopedHidden, taskId);
  }

  /// Finds which [TaskTier] currently contains [taskId], or `null` if not found.
  TaskTier? findTierOfTask(String taskId) {
    for (final tier in TaskTier.values) {
      if (_findInList(tasksForTier(tier), taskId) != null) return tier;
    }
    return null;
  }

  /// Returns the task list for a given [tier].
  List<TaskItem> tasksForTier(TaskTier tier) => switch (tier) {
    TaskTier.focus => focus,
    TaskTier.ready => ready,
    TaskTier.planned => planned,
    TaskTier.blocked => blocked,
    TaskTier.someday => someday,
    TaskTier.completed => completed,
  };

  /// Finds a task with [taskId] inside [list], or `null` if absent.
  static TaskItem? _findInList(List<TaskItem> list, String taskId) {
    for (final task in list) {
      if (task.id == taskId) return task;
    }
    return null;
  }
}

/// Stateless scheduling, blocking, downgrade, restore, and shared queue ordering
/// mutation engine per `TDF_SPEC.md` Sections 6.2, 6.3, 6.5, and 6.11.
@immutable
class TaskBoardQueueMutator {
  /// Private constructor for static queue and tier transition helpers.
  const TaskBoardQueueMutator._();

  /// Appends [taskId] to [queue] if not already present, advancing `queue.modified` when changed.
  static TdfQueueBlock appendTaskToQueue(
    TdfQueueBlock queue,
    String taskId,
    DateTime now,
  ) {
    if (queue.taskIds.contains(taskId)) return queue;
    if (queue.taskIds.length >= TdfQueueBlock.maxQueueEntries) {
      throw const FormatException('LimitExceeded');
    }
    return TdfQueueBlock(
      modifiedAt: TaskItem.nextModifiedTimestamp(now, queue.modifiedAt),
      taskIds: <String>[...queue.taskIds, taskId],
    );
  }

  /// Moves an active task on [board] immediately to Tier 4 (`Blocked`) and refills vacated active slots.
  static NormalizedTierSlices blockTask(
    NormalizedTierSlices board,
    String taskId, {
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    DateTime? suspendedUntil,
  }) {
    final now = TaskItem.normalizeTimestamp(
      currentDate ?? DateTime.now().toUtc(),
    );
    final sourceTier = board.findTierOfTask(taskId);
    final task = board.findTask(taskId);
    if (sourceTier == null || sourceTier == TaskTier.blocked || task == null) {
      return board;
    }

    final wasCompleted = task.isCompleted || task.completedAt != null;
    final useForever =
        suspendedUntil == null || suspendedUntil == TaskItem.defaultSuspendedAt;
    final blockedTask = task.copyWith(
      isCompleted: false,
      clearCompletedAt: true,
      isPriority: false,
      suspendedAt: useForever ? null : suspendedUntil,
      clearSuspendedAt: useForever,
      isSuspendedForever: useForever,
      subtasks: wasCompleted
          ? setAllSubtasksCompleted(task.subtasks, false)
          : task.subtasks,
      modifiedAt: TaskItem.nextModifiedTimestamp(now, task.effectiveModifiedAt),
    );
    final nextQueueBlock = appendTaskToQueue(board.queueBlock, taskId, now);
    final updatedTasks = _replaceTaskInList(board.allTasks, blockedTask);

    return TaskBoardEvaluator.reevaluateBoard(
      board,
      tasks: updatedTasks,
      queueBlock: nextQueueBlock,
      now: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
    ).logDomainMutation('blockTask id=$taskId');
  }

  /// Captures the required completion number for a newly added or rearmed prerequisite [target] per `TDF_SPEC.md` Section 6.9.3.
  static int captureDependencyRequirement(TaskItem? target) {
    if (target == null) return 1;
    if (target.isCompleted || target.completedAt != null) {
      return target.completions >= 1 ? target.completions : 1;
    }
    if (target.completions >= TdfTaskDependency.maxCompletions) {
      throw const FormatException('LimitExceeded');
    }
    return target.completions + 1;
  }

  /// Downgrades a task on [board] in `Focus` (to `Ready`), `Ready` (to `Planned`), or `Planned` (to `Someday`) per `TDF_SPEC_0.6.0.md` Section 6.3.
  static NormalizedTierSlices downgradeTask(
    NormalizedTierSlices board,
    String taskId, {
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    String? activeLabelId,
    double? currentLatitude,
    double? currentLongitude,
  }) {
    final now = TaskItem.normalizeTimestamp(
      currentDate ?? DateTime.now().toUtc(),
    );
    final task = board.findTask(taskId);
    if (task == null) return board;
    final hasActiveContext =
        (activeLabelId != null && activeLabelId.isNotEmpty) ||
        (currentLatitude != null && currentLongitude != null);
    final contextBoard = hasActiveContext
        ? TaskBoardEvaluator.evaluate(
            tasks: board.allTasks,
            evaluationTime: now,
            localEvaluationTime: localEvaluationTime,
            timeZone: timeZone,
            labels: board.labels,
            locations: board.locations,
            deletedBlock: board.deletedBlock,
            queueBlock: board.queueBlock,
            activeLabelId: activeLabelId,
            currentLatitude: currentLatitude,
            currentLongitude: currentLongitude,
            pruneExpiredCompleted: false,
          )
        : board;
    final sourceTier = contextBoard.findTierOfTask(taskId);
    if (sourceTier == null) return board;

    if (sourceTier == TaskTier.focus) {
      return _downgradeFromFocus(
        board,
        contextBoard,
        task,
        now,
        localEvaluationTime: localEvaluationTime,
        timeZone: timeZone,
      ).logDomainMutation('downgradeTask id=$taskId from=Focus');
    }
    if (sourceTier == TaskTier.ready) {
      return _downgradeToQueueTail(
        board,
        task,
        now,
        localEvaluationTime: localEvaluationTime,
        timeZone: timeZone,
      ).logDomainMutation('downgradeTask id=$taskId from=Ready');
    }
    if (sourceTier == TaskTier.planned) {
      return _downgradeToSomeday(
        board,
        task,
        now,
        localEvaluationTime: localEvaluationTime,
        timeZone: timeZone,
      ).logDomainMutation('downgradeTask id=$taskId from=Planned');
    }
    return board;
  }

  /// Moves [taskId] within [board.queueBlock] before [beforeTaskId], after [afterTaskId], or to the end per `TDF_SPEC.md` Section 6.11.1.
  static NormalizedTierSlices moveTaskInQueue(
    NormalizedTierSlices board,
    String taskId, {
    String? beforeTaskId,
    String? afterTaskId,
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  }) {
    final currentIds = board.queueBlock.taskIds;
    if (!currentIds.contains(taskId)) return board;
    if (beforeTaskId != null &&
        (beforeTaskId == taskId || !currentIds.contains(beforeTaskId))) {
      return board;
    }
    if (afterTaskId != null &&
        (afterTaskId == taskId || !currentIds.contains(afterTaskId))) {
      return board;
    }
    final withoutTask = <String>[
      for (final id in currentIds)
        if (id != taskId) id,
    ];
    final nextIds = _insertMovedQueueId(
      withoutTask: withoutTask,
      taskId: taskId,
      beforeTaskId: beforeTaskId,
      afterTaskId: afterTaskId,
    );
    if (listEquals(nextIds, currentIds)) return board;

    final now = TaskItem.normalizeTimestamp(
      currentDate ?? DateTime.now().toUtc(),
    );
    final nextQueue = TdfQueueBlock(
      modifiedAt: TaskItem.nextModifiedTimestamp(
        now,
        board.queueBlock.modifiedAt,
      ),
      taskIds: nextIds,
    );
    return TaskBoardEvaluator.reevaluateBoard(
      board,
      queueBlock: nextQueue,
      now: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      pruneExpiredCompleted: false,
    ).logDomainMutation('moveTaskInQueue id=$taskId');
  }

  /// Rearms [dependencies] on [board] for the next occurrence of a recurring or restored task per `TDF_SPEC.md` Section 6.9.3.
  static List<TdfTaskDependency> rearmDependencies(
    NormalizedTierSlices board,
    List<TdfTaskDependency> dependencies,
  ) => List.unmodifiable([
    for (final item in dependencies)
      if (board.findTask(item.taskId) case final target?)
        TdfTaskDependency(
          taskId: item.taskId,
          requiredCompletion: captureDependencyRequirement(target),
        )
      else
        item,
  ]);

  /// Reconciles [currentQueue] when `copyWith` replaces tier slices without providing an explicit `queueBlock`.
  static TdfQueueBlock reconcileQueueWithSlices({
    required TdfQueueBlock currentQueue,
    required List<TaskItem> focus,
    required List<TaskItem> ready,
    required List<TaskItem> planned,
    required List<TaskItem> blocked,
    required Set<String> previousUnqueuedBlockedIds,
  }) {
    final scheduledOpenIds = <String>{};
    final orderedSliceIds = <String>[];
    for (final task in <TaskItem>[...focus, ...ready, ...planned]) {
      if (!task.isCompleted &&
          task.completedAt == null &&
          scheduledOpenIds.add(task.id)) {
        orderedSliceIds.add(task.id);
      }
    }
    for (final task in blocked) {
      if (!task.isCompleted &&
          task.completedAt == null &&
          scheduledOpenIds.add(task.id) &&
          !previousUnqueuedBlockedIds.contains(task.id)) {
        orderedSliceIds.add(task.id);
      }
    }
    final reconciled = <String>[
      for (final id in currentQueue.taskIds)
        if (scheduledOpenIds.contains(id)) id,
    ];
    for (final id in orderedSliceIds) {
      if (!reconciled.contains(id)) reconciled.add(id);
    }
    if (listEquals(reconciled, currentQueue.taskIds)) return currentQueue;
    return TdfQueueBlock(
      modifiedAt: currentQueue.modifiedAt,
      taskIds: reconciled,
    );
  }

  /// Removes [taskId] from [queue] if present, advancing `queue.modified` when changed.
  static TdfQueueBlock removeTaskFromQueue(
    TdfQueueBlock queue,
    String taskId,
    DateTime now,
  ) {
    if (!queue.taskIds.contains(taskId)) return queue;
    return TdfQueueBlock(
      modifiedAt: TaskItem.nextModifiedTimestamp(now, queue.modifiedAt),
      taskIds: <String>[
        for (final id in queue.taskIds)
          if (id != taskId) id,
      ],
    );
  }

  /// Restores a completed task on [board] back into `Someday`, `Planned`, or `Focus` per `TDF_SPEC.md` Section 6.5.
  static NormalizedTierSlices restoreTask(
    NormalizedTierSlices board,
    String taskId, {
    TaskTier targetTier = TaskTier.planned,
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  }) {
    if (targetTier == TaskTier.completed) return board;
    final now = TaskItem.normalizeTimestamp(
      currentDate ?? DateTime.now().toUtc(),
    );
    final existing = board.findTask(taskId);
    if (existing == null ||
        (!existing.isCompleted && existing.completedAt == null)) {
      return board;
    }

    final isSomeday = targetTier == TaskTier.someday;
    final restored = existing.copyWith(
      isCompleted: false,
      clearCompletedAt: true,
      clearSuspendedAt: true,
      isSuspendedForever: false,
      clearDueAt: true,
      isPriority: targetTier == TaskTier.focus,
      dependencies: rearmDependencies(board, existing.dependencies),
      subtasks: setAllSubtasksCompleted(existing.subtasks, false),
      modifiedAt: TaskItem.nextModifiedTimestamp(
        now,
        existing.effectiveModifiedAt,
      ),
    );
    final updatedTasks = _replaceTaskInList(board.allTasks, restored);
    final nextQueueBlock = isSomeday
        ? removeTaskFromQueue(board.queueBlock, taskId, now)
        : appendTaskToQueue(board.queueBlock, taskId, now);

    return TaskBoardEvaluator.reevaluateBoard(
      board,
      tasks: updatedTasks,
      queueBlock: nextQueueBlock,
      now: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
    ).logDomainMutation('restoreTask id=$taskId targetTier=${targetTier.name}');
  }

  /// Schedules a task on [board] from `Someday` into the active pull cycle per `TDF_SPEC.md` Section 6.2.
  static NormalizedTierSlices scheduleTask(
    NormalizedTierSlices board,
    String taskId, {
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    bool isPriority = false,
  }) {
    final now = TaskItem.normalizeTimestamp(
      currentDate ?? DateTime.now().toUtc(),
    );
    final existing = board.findTask(taskId);
    if (existing == null) return board;

    final wasCompleted = existing.isCompleted || existing.completedAt != null;
    final effectivePriority = isPriority || existing.isPriority;
    final taskAttributesChanged =
        wasCompleted || effectivePriority != existing.isPriority;
    final scheduled = taskAttributesChanged
        ? existing.copyWith(
            isCompleted: false,
            clearCompletedAt: true,
            clearSuspendedAt: wasCompleted,
            isSuspendedForever: wasCompleted
                ? false
                : existing.isSuspendedForever,
            isPriority: effectivePriority,
            dependencies: wasCompleted
                ? rearmDependencies(board, existing.dependencies)
                : existing.dependencies,
            subtasks: wasCompleted
                ? setAllSubtasksCompleted(existing.subtasks, false)
                : existing.subtasks,
            modifiedAt: TaskItem.nextModifiedTimestamp(
              now,
              existing.effectiveModifiedAt,
            ),
          )
        : existing;
    final updatedTasks = _replaceTaskInList(board.allTasks, scheduled);
    final nextQueueBlock = appendTaskToQueue(board.queueBlock, taskId, now);

    return TaskBoardEvaluator.reevaluateBoard(
      board,
      tasks: updatedTasks,
      queueBlock: nextQueueBlock,
      now: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
    ).logDomainMutation('scheduleTask id=$taskId');
  }

  /// Returns a list of [steps] with every step's `isCompleted` state set to [isCompleted].
  static List<SubtaskItem> setAllSubtasksCompleted(
    List<SubtaskItem> steps,
    bool isCompleted,
  ) => [
    for (final step in steps)
      step.isCompleted == isCompleted
          ? step
          : step.copyWith(isCompleted: isCompleted),
  ];

  /// Updates [currentQueue] after [existingTask] is edited or added as [updatedTask].
  static TdfQueueBlock updateQueueForEditedTask(
    TdfQueueBlock currentQueue,
    TaskItem? existingTask,
    TaskItem updatedTask,
    bool shouldBeQueued,
    DateTime now,
  ) {
    if (!shouldBeQueued) {
      return removeTaskFromQueue(currentQueue, updatedTask.id, now);
    }
    final wasDone =
        (existingTask?.isCompleted ?? false) ||
        existingTask?.completedAt != null;
    final baseQueue = wasDone
        ? removeTaskFromQueue(currentQueue, updatedTask.id, now)
        : currentQueue;
    return appendTaskToQueue(baseQueue, updatedTask.id, now);
  }

  /// Downgrades [task] on [board] from Tier 1 (`Focus`) to Tier 2 (`Ready`) using the active-filter-relative anchor $E_{\text{ctx}}$ in [contextBoard] per `TDF_SPEC_0.6.0.md` Section 6.3.
  static NormalizedTierSlices _downgradeFromFocus(
    NormalizedTierSlices board,
    NormalizedTierSlices contextBoard,
    TaskItem task,
    DateTime now, {
    required DateTime? localEvaluationTime,
    required TdfTimeZoneContext? timeZone,
  }) {
    final eligibleWithoutTask = <TaskItem>[
      for (final candidate in <TaskItem>[
        ...contextBoard.focus,
        ...contextBoard.ready,
        ...contextBoard.planned,
      ])
        if (candidate.id != task.id) candidate,
    ];
    const readyEndAfterExcludingTarget =
        TaskBoardEvaluator.focusSoftLimit +
        TaskBoardEvaluator.readySoftLimit -
        1;
    final TaskItem? anchorTask;
    final bool alignedPriority;
    if (eligibleWithoutTask.isEmpty) {
      anchorTask = null;
      alignedPriority = false;
    } else if (eligibleWithoutTask.length < readyEndAfterExcludingTarget) {
      anchorTask = eligibleWithoutTask.last;
      alignedPriority = false;
    } else {
      anchorTask = eligibleWithoutTask[readyEndAfterExcludingTarget - 1];
      alignedPriority = anchorTask.isPriority;
    }

    final priorityChanged = task.isPriority != alignedPriority;
    final updatedTask = priorityChanged
        ? task.copyWith(
            isPriority: alignedPriority,
            modifiedAt: TaskItem.nextModifiedTimestamp(
              now,
              task.effectiveModifiedAt,
            ),
          )
        : task;

    final List<String> nextQueueIds;
    if (anchorTask == null) {
      nextQueueIds = board.queueBlock.taskIds;
    } else {
      final reordered = <String>[];
      for (final id in board.queueBlock.taskIds) {
        if (id == task.id) continue;
        reordered.add(id);
        if (id == anchorTask.id) reordered.add(task.id);
      }
      if (!reordered.contains(task.id)) reordered.add(task.id);
      nextQueueIds = reordered;
    }

    final queueChanged = !listEquals(nextQueueIds, board.queueBlock.taskIds);
    if (!priorityChanged && !queueChanged) return board;

    final nextQueueBlock = queueChanged
        ? TdfQueueBlock(
            modifiedAt: TaskItem.nextModifiedTimestamp(
              now,
              board.queueBlock.modifiedAt,
            ),
            taskIds: nextQueueIds,
          )
        : board.queueBlock;
    final updatedTasks = _replaceTaskInList(board.allTasks, updatedTask);

    return TaskBoardEvaluator.reevaluateBoard(
      board,
      tasks: updatedTasks,
      queueBlock: nextQueueBlock,
      now: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
    );
  }

  /// Removes `priority` from [task] on [board] and moves its queue entry to the end of `queue` (`TDF_SPEC.md` Section 6.3).
  static NormalizedTierSlices _downgradeToQueueTail(
    NormalizedTierSlices board,
    TaskItem task,
    DateTime now, {
    required DateTime? localEvaluationTime,
    required TdfTimeZoneContext? timeZone,
  }) {
    final priorityChanged = task.isPriority;
    final nextQueueIds = <String>[
      for (final id in board.queueBlock.taskIds)
        if (id != task.id) id,
      task.id,
    ];
    final queueChanged = !listEquals(nextQueueIds, board.queueBlock.taskIds);
    if (!priorityChanged && !queueChanged) return board;

    final updatedTask = priorityChanged
        ? task.copyWith(
            isPriority: false,
            modifiedAt: TaskItem.nextModifiedTimestamp(
              now,
              task.effectiveModifiedAt,
            ),
          )
        : task;
    final nextQueueBlock = queueChanged
        ? TdfQueueBlock(
            modifiedAt: TaskItem.nextModifiedTimestamp(
              now,
              board.queueBlock.modifiedAt,
            ),
            taskIds: nextQueueIds,
          )
        : board.queueBlock;
    final updatedTasks = _replaceTaskInList(board.allTasks, updatedTask);

    return TaskBoardEvaluator.reevaluateBoard(
      board,
      tasks: updatedTasks,
      queueBlock: nextQueueBlock,
      now: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
    );
  }

  /// Downgrades [task] on [board] from Tier 3 (`Planned`) to Tier 5 (`Someday`) per `TDF_SPEC.md` Section 6.3.
  static NormalizedTierSlices _downgradeToSomeday(
    NormalizedTierSlices board,
    TaskItem task,
    DateTime now, {
    required DateTime? localEvaluationTime,
    required TdfTimeZoneContext? timeZone,
  }) {
    final taskAttributesChanged =
        task.isPriority ||
        task.suspendedAt != null ||
        task.isSuspendedForever ||
        task.isCompleted ||
        task.completedAt != null;
    final downgradedTask = taskAttributesChanged
        ? task.toActive(
            isPriority: false,
            modifiedAt: TaskItem.nextModifiedTimestamp(
              now,
              task.effectiveModifiedAt,
            ),
          )
        : task;
    final nextQueueBlock = removeTaskFromQueue(board.queueBlock, task.id, now);
    final updatedTasks = _replaceTaskInList(board.allTasks, downgradedTask);

    return TaskBoardEvaluator.reevaluateBoard(
      board,
      tasks: updatedTasks,
      queueBlock: nextQueueBlock,
      now: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
    );
  }

  /// Inserts [taskId] into [withoutTask] before [beforeTaskId], after [afterTaskId], or at the end.
  static List<String> _insertMovedQueueId({
    required List<String> withoutTask,
    required String taskId,
    required String? beforeTaskId,
    required String? afterTaskId,
  }) {
    if (beforeTaskId != null) {
      final nextIds = <String>[];
      for (final id in withoutTask) {
        if (id == beforeTaskId) nextIds.add(taskId);
        nextIds.add(id);
      }
      return nextIds;
    }
    if (afterTaskId != null) {
      final nextIds = <String>[];
      for (final id in withoutTask) {
        nextIds.add(id);
        if (id == afterTaskId) nextIds.add(taskId);
      }
      return nextIds;
    }
    return <String>[...withoutTask, taskId];
  }

  /// Replaces the task matching `replacement.id` inside [tasks].
  static List<TaskItem> _replaceTaskInList(
    List<TaskItem> tasks,
    TaskItem replacement,
  ) => <TaskItem>[
    for (final item in tasks) item.id == replacement.id ? replacement : item,
  ];
}
