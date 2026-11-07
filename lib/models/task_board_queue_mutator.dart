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

import 'task_board.dart';
import 'task_board_evaluator.dart';
import 'task_board_mutator.dart';
import 'task_item.dart';
import 'task_tier.dart';
import 'tdf_sync_metadata.dart';
import 'tdf_timezone.dart';

/// Stateless scheduling, blocking, downgrade, restore, and shared queue ordering
/// mutation engine for [TaskBoard] per `TDF_SPEC.md` Sections 6.2, 6.3, 6.5, and 6.11.
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
  static TaskBoard blockTask(
    TaskBoard board,
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
          ? TaskBoardMutator.setAllSubtasksCompleted(task.subtasks, false)
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

  /// Derives a [TdfQueueBlock] preserving the slice order of `[focus, ready, planned, blocked]`.
  static TdfQueueBlock deriveSliceQueueBlock({
    required List<TaskItem> focus,
    required List<TaskItem> ready,
    required List<TaskItem> planned,
    required List<TaskItem> blocked,
  }) {
    final ids = <String>[];
    final seen = <String>{};
    DateTime? latestModified;
    for (final task in <TaskItem>[...focus, ...ready, ...planned, ...blocked]) {
      if (!task.isCompleted && task.completedAt == null && seen.add(task.id)) {
        ids.add(task.id);
        final effectiveMod = task.effectiveModifiedAt;
        if (latestModified == null || effectiveMod.isAfter(latestModified)) {
          latestModified = effectiveMod;
        }
      }
    }
    return TdfQueueBlock(
      modifiedAt: latestModified ?? TdfQueueBlock.epochModifiedAt,
      taskIds: ids,
    );
  }

  /// Downgrades a task on [board] in `Focus` (to `Ready`), `Ready` (to `Planned`), or `Planned` (to `Someday`) per `TDF_SPEC.md` Section 6.3.
  static TaskBoard downgradeTask(
    TaskBoard board,
    String taskId, {
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  }) {
    final now = TaskItem.normalizeTimestamp(
      currentDate ?? DateTime.now().toUtc(),
    );
    final sourceTier = board.findTierOfTask(taskId);
    final task = board.findTask(taskId);
    if (sourceTier == null || task == null) return board;

    if (sourceTier == TaskTier.focus) {
      return _downgradeFromFocus(
        board,
        task,
        now,
        localEvaluationTime: localEvaluationTime,
        timeZone: timeZone,
      ).logDomainMutation('downgradeTask id=$taskId from=Focus');
    }
    if (sourceTier == TaskTier.ready) {
      return _downgradeToPlanned(
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
  static TaskBoard moveTaskInQueue(
    TaskBoard board,
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
  static TaskBoard restoreTask(
    TaskBoard board,
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
      isPriority: targetTier == TaskTier.focus,
      dependencies: TaskBoardMutator.rearmDependencies(
        board,
        existing.dependencies,
      ),
      subtasks: TaskBoardMutator.setAllSubtasksCompleted(
        existing.subtasks,
        false,
      ),
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
  static TaskBoard scheduleTask(
    TaskBoard board,
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
                ? TaskBoardMutator.rearmDependencies(
                    board,
                    existing.dependencies,
                  )
                : existing.dependencies,
            subtasks: wasCompleted
                ? TaskBoardMutator.setAllSubtasksCompleted(
                    existing.subtasks,
                    false,
                  )
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

  /// Updates [currentQueue] after [existingTask] is edited or added as [updatedTask].
  static TdfQueueBlock updateQueueForEditedTask(
    TdfQueueBlock currentQueue,
    TaskItem? existingTask,
    TaskItem updatedTask,
    bool shouldBeQueued,
    DateTime now,
  ) {
    final wasCompleted =
        existingTask != null &&
        (existingTask.isCompleted || existingTask.completedAt != null);
    if (!shouldBeQueued) {
      return removeTaskFromQueue(currentQueue, updatedTask.id, now);
    }
    if (wasCompleted) {
      final withoutTask = removeTaskFromQueue(
        currentQueue,
        updatedTask.id,
        now,
      );
      return appendTaskToQueue(withoutTask, updatedTask.id, now);
    }
    return appendTaskToQueue(currentQueue, updatedTask.id, now);
  }

  /// Downgrades [task] on [board] from Tier 1 (`Focus`) to Tier 2 (`Ready`) per `TDF_SPEC.md` Section 6.3.
  static TaskBoard _downgradeFromFocus(
    TaskBoard board,
    TaskItem task,
    DateTime now, {
    required DateTime? localEvaluationTime,
    required TdfTimeZoneContext? timeZone,
  }) {
    final totalEligibleCount =
        board.focus.length + board.ready.length + board.planned.length;
    if (totalEligibleCount <
        TaskBoard.focusSoftLimit + TaskBoard.readySoftLimit) {
      return _downgradeToQueueTail(
        board,
        task,
        now,
        localEvaluationTime: localEvaluationTime,
        timeZone: timeZone,
      );
    }

    final slot8Anchor = board.ready[TaskBoard.readySoftLimit - 1];
    final alignedPriority = slot8Anchor.isPriority;
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

    final nextQueueIds = <String>[];
    for (final id in board.queueBlock.taskIds) {
      if (id == task.id) continue;
      nextQueueIds.add(id);
      if (id == slot8Anchor.id) nextQueueIds.add(task.id);
    }
    if (!nextQueueIds.contains(task.id)) nextQueueIds.add(task.id);

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

  /// Downgrades [task] on [board] from Tier 2 (`Ready`) to Tier 3 (`Planned`) per `TDF_SPEC.md` Section 6.3.
  static TaskBoard _downgradeToPlanned(
    TaskBoard board,
    TaskItem task,
    DateTime now, {
    required DateTime? localEvaluationTime,
    required TdfTimeZoneContext? timeZone,
  }) => _downgradeToQueueTail(
    board,
    task,
    now,
    localEvaluationTime: localEvaluationTime,
    timeZone: timeZone,
  );

  /// Removes `priority` from [task] on [board] and moves its queue entry to the end of `queue` (`TDF_SPEC.md` Section 6.3).
  static TaskBoard _downgradeToQueueTail(
    TaskBoard board,
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
  static TaskBoard _downgradeToSomeday(
    TaskBoard board,
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
