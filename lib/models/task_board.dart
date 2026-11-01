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

import 'task_item.dart';
import 'task_tier.dart';

/// Immutable domain model representing the entire TierTask board across all 6 tiers (`1` to `6`).
@immutable
class TaskBoard {
  /// Creates an immutable [TaskBoard] with unmodifiable task lists for tiers `1` to `6`.
  TaskBoard({
    List<TaskItem> focus = const [],
    List<TaskItem> ready = const [],
    List<TaskItem> planned = const [],
    List<TaskItem> blocked = const [],
    List<TaskItem> someday = const [],
    List<TaskItem> completed = const [],
  }) : focus = List<TaskItem>.unmodifiable(focus),
       ready = List<TaskItem>.unmodifiable(ready),
       planned = List<TaskItem>.unmodifiable(planned),
       blocked = List<TaskItem>.unmodifiable(blocked),
       someday = List<TaskItem>.unmodifiable(someday),
       completed = List<TaskItem>.unmodifiable(completed);

  /// Creates an empty [TaskBoard] across all 6 tiers.
  factory TaskBoard.empty() => TaskBoard();

  /// Retention period in days for completed tasks in Tier 6 (`# [6] Completed`).
  static const int completedRetentionDays = 30;

  /// Soft WIP limit for Tier 1 (`# [1] Focus`).
  static const int focusSoftLimit = 3;

  /// Soft WIP limit for Tier 2 (`# [2] Ready`).
  static const int readySoftLimit = 5;

  /// Tier 1 (`# [1] Focus`) task items.
  final List<TaskItem> focus;

  /// Tier 2 (`# [2] Ready`) task items.
  final List<TaskItem> ready;

  /// Tier 3 (`# [3] Planned`) task items.
  final List<TaskItem> planned;

  /// Tier 4 (`# [4] Blocked`) task items.
  final List<TaskItem> blocked;

  /// Tier 5 (`# [5] Someday`) task items.
  final List<TaskItem> someday;

  /// Tier 6 (`# [6] Completed`) task items.
  final List<TaskItem> completed;

  /// Adds a new task to [targetTier] (defaulting to Tier 3 `# [3] Planned`),
  /// prunes expired completed tasks, and runs the Auto-Pull Cascade.
  TaskBoard addTask(
    String title, {
    TaskTier targetTier = TaskTier.planned,
    bool isPriority = false,
    List<SubtaskItem> subtasks = const [],
    DateTime? currentDate,
    String? id,
  }) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return this;
    }

    final now = currentDate ?? DateTime.now();
    final effectiveTier = isPriority && targetTier == TaskTier.planned
        ? TaskTier.focus
        : targetTier;
    final isDoneTier = effectiveTier == TaskTier.completed;
    final cleanSubtasks = [
      for (final subtask in subtasks)
        if (subtask.title.trim().isNotEmpty)
          SubtaskItem(
            title: subtask.title.trim(),
            isCompleted: subtask.isCompleted,
          ),
    ];
    final newTask = isDoneTier
        ? TaskItem(
            id: id,
            title: trimmed,
            isPriority: isPriority,
            subtasks: cleanSubtasks,
          ).toCompleted(now)
        : TaskItem(
            id: id,
            title: trimmed,
            isCompleted: false,
            isPriority: isPriority,
            subtasks: cleanSubtasks,
          );

    final updated = _appendTaskToTier(newTask, effectiveTier);
    return updated.pruneCompletedTasks(currentDate: now).applyAutoPull();
  }

  /// Executes the Auto-Pull Cascade (Soft WIP Limits):
  /// - Step 1: Fills Tier 1 (`focus`, limit 3) from the top of Tier 2 (`ready`).
  /// - Step 2: Fills Tier 2 (`ready`, limit 5) from the top of Tier 3 (`planned`).
  /// - Repeats if Tier 1 still has capacity after Tier 2 is refilled from Tier 3.
  /// - Never force-demotes excess items when a tier is manually overfilled.
  /// - Static tiers (`blocked`, `someday`, `completed`) are never pulled automatically.
  TaskBoard applyAutoPull() {
    final nextFocus = List<TaskItem>.from(focus);
    final nextReady = List<TaskItem>.from(ready);
    final nextPlanned = List<TaskItem>.from(planned);

    _cascadeQueues(
      nextFocus: nextFocus,
      nextReady: nextReady,
      nextPlanned: nextPlanned,
    );

    return copyWith(focus: nextFocus, ready: nextReady, planned: nextPlanned);
  }

  /// Moves an active task immediately to Tier 4 (`# [4] Blocked`) and triggers
  /// the Auto-Pull Cascade to refill any vacated slot.
  TaskBoard blockTask(String taskId, {DateTime? currentDate}) {
    return moveTask(taskId, TaskTier.blocked, currentDate: currentDate);
  }

  /// Marks an active task as done:
  /// 1. Stamps it with `- [x] YYYY-MM-DD` and inserts it at the top of Tier 6 (`completed`).
  /// 2. Prunes items in Tier 6 older than 30 days.
  /// 3. Triggers the Auto-Pull Cascade to refill Tier 1 and Tier 2.
  TaskBoard completeTask(String taskId, {DateTime? currentDate}) {
    final now = currentDate ?? DateTime.now();
    final sourceTier = findTierOfTask(taskId);
    if (sourceTier == null || sourceTier == TaskTier.completed) {
      return this;
    }
    final task = findTask(taskId);
    if (task == null) {
      return this;
    }

    final completedTask = task.toCompleted(now);
    final updated = _removeTaskFromTier(
      taskId,
      sourceTier,
    ).copyWith(completed: [completedTask, ...completed]);

    return updated.pruneCompletedTasks(currentDate: now).applyAutoPull();
  }

  /// Returns a copy of this [TaskBoard] with the specified tier lists replaced.
  TaskBoard copyWith({
    List<TaskItem>? focus,
    List<TaskItem>? ready,
    List<TaskItem>? planned,
    List<TaskItem>? blocked,
    List<TaskItem>? someday,
    List<TaskItem>? completed,
  }) {
    return TaskBoard(
      focus: focus ?? this.focus,
      ready: ready ?? this.ready,
      planned: planned ?? this.planned,
      blocked: blocked ?? this.blocked,
      someday: someday ?? this.someday,
      completed: completed ?? this.completed,
    );
  }

  /// Permanently deletes a task and runs the Auto-Pull Cascade if an active slot opened.
  TaskBoard deleteTask(String taskId, {DateTime? currentDate}) {
    final now = currentDate ?? DateTime.now();
    final tier = findTierOfTask(taskId);
    if (tier == null) {
      return this;
    }

    return _removeTaskFromTier(
      taskId,
      tier,
    ).pruneCompletedTasks(currentDate: now).applyAutoPull();
  }

  /// Downgrades a task one active tier down (`focus -> ready` or `ready -> planned`)
  /// while pulling replacement candidates upward first to prevent ping-pong bounce.
  TaskBoard downgradeTask(String taskId, {DateTime? currentDate}) {
    final now = currentDate ?? DateTime.now();
    final sourceTier = findTierOfTask(taskId);
    if (sourceTier == null) {
      return this;
    }
    final task = findTask(taskId);
    if (task == null) {
      return this;
    }

    if (sourceTier == TaskTier.focus) {
      return _downgradeFromFocus(task.toActive(), now);
    }
    if (sourceTier == TaskTier.ready) {
      return _downgradeFromReady(task.toActive(), now);
    }
    return this;
  }

  /// Updates the title of an existing task.
  TaskBoard editTaskTitle(String taskId, String newTitle) {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) {
      return this;
    }
    final tier = findTierOfTask(taskId);
    if (tier == null) {
      return this;
    }

    return switch (tier) {
      TaskTier.focus => copyWith(focus: _renameInList(focus, taskId, trimmed)),
      TaskTier.ready => copyWith(ready: _renameInList(ready, taskId, trimmed)),
      TaskTier.planned => copyWith(
        planned: _renameInList(planned, taskId, trimmed),
      ),
      TaskTier.blocked => copyWith(
        blocked: _renameInList(blocked, taskId, trimmed),
      ),
      TaskTier.someday => copyWith(
        someday: _renameInList(someday, taskId, trimmed),
      ),
      TaskTier.completed => copyWith(
        completed: _renameInList(completed, taskId, trimmed),
      ),
    };
  }

  /// Finds the [TaskItem] with [taskId], or `null` if not found.
  TaskItem? findTask(String taskId) {
    for (final tier in TaskTier.values) {
      if (_findInList(tasksForTier(tier), taskId) case final found?) {
        return found;
      }
    }
    return null;
  }

  /// Finds which [TaskTier] currently contains [taskId], or `null` if not found.
  TaskTier? findTierOfTask(String taskId) {
    for (final tier in TaskTier.values) {
      if (_findInList(tasksForTier(tier), taskId) != null) {
        return tier;
      }
    }
    return null;
  }

  /// Moves a task to [targetTier], respecting anti-ping-pong rules when moving downward
  /// and triggering the Auto-Pull Cascade when slots open or tasks enter active queues.
  TaskBoard moveTask(
    String taskId,
    TaskTier targetTier, {
    DateTime? currentDate,
  }) {
    final now = currentDate ?? DateTime.now();
    final sourceTier = findTierOfTask(taskId);
    if (sourceTier == null || sourceTier == targetTier) {
      return this;
    }
    if (targetTier == TaskTier.completed) {
      return completeTask(taskId, currentDate: now);
    }
    if (sourceTier == TaskTier.completed) {
      return restoreTask(taskId, targetTier, currentDate: now);
    }
    if ((sourceTier == TaskTier.focus && targetTier == TaskTier.ready) ||
        (sourceTier == TaskTier.ready && targetTier == TaskTier.planned)) {
      return downgradeTask(taskId, currentDate: now);
    }

    final task = findTask(taskId);
    if (task == null) {
      return this;
    }
    final activeTask = task.toActive();

    if (sourceTier == TaskTier.focus && targetTier == TaskTier.planned) {
      final afterRemovalAndPull = _removeTaskFromTier(
        taskId,
        TaskTier.focus,
      ).applyAutoPull();
      return afterRemovalAndPull
          ._appendTaskToTier(activeTask, TaskTier.planned)
          .pruneCompletedTasks(currentDate: now);
    }

    return _removeTaskFromTier(taskId, sourceTier)
        ._appendTaskToTier(activeTask, targetTier)
        .pruneCompletedTasks(currentDate: now)
        .applyAutoPull();
  }

  /// Prunes tasks in Tier 6 (`# [6] Completed`) older than 30 days (UTC).
  TaskBoard pruneCompletedTasks({DateTime? currentDate}) {
    final now = currentDate ?? DateTime.now();
    final normalizedNow = DateTime.utc(now.year, now.month, now.day);

    final retained = <TaskItem>[];
    for (final task in completed) {
      if (_isWithinRetention(task, normalizedNow)) {
        retained.add(task);
      }
    }

    return copyWith(completed: retained);
  }

  /// Restores a completed task from Tier 6 (`# [6] Completed`) into [targetTier],
  /// stripping `[x]` and the `YYYY-MM-DD` timestamp and running the Auto-Pull Cascade.
  TaskBoard restoreTask(
    String taskId,
    TaskTier targetTier, {
    DateTime? currentDate,
  }) {
    if (targetTier == TaskTier.completed) {
      return this;
    }
    final sourceTier = findTierOfTask(taskId);
    if (sourceTier != TaskTier.completed) {
      return this;
    }
    final task = findTask(taskId);
    if (task == null) {
      return this;
    }

    final now = currentDate ?? DateTime.now();
    final restoredTask = task.toActive();

    return _removeTaskFromTier(taskId, TaskTier.completed)
        ._appendTaskToTier(restoredTask, targetTier)
        .pruneCompletedTasks(currentDate: now)
        .applyAutoPull();
  }

  /// Returns the task list for a given [tier].
  List<TaskItem> tasksForTier(TaskTier tier) {
    return switch (tier) {
      TaskTier.focus => focus,
      TaskTier.ready => ready,
      TaskTier.planned => planned,
      TaskTier.blocked => blocked,
      TaskTier.someday => someday,
      TaskTier.completed => completed,
    };
  }

  /// Appends [task] to [tier] (prepending when [tier] is [TaskTier.completed]).
  TaskBoard _appendTaskToTier(TaskItem task, TaskTier tier) {
    return switch (tier) {
      TaskTier.focus => copyWith(focus: [...focus, task]),
      TaskTier.ready => copyWith(ready: [...ready, task]),
      TaskTier.planned => copyWith(planned: [...planned, task]),
      TaskTier.blocked => copyWith(blocked: [...blocked, task]),
      TaskTier.someday => copyWith(someday: [...someday, task]),
      TaskTier.completed => copyWith(completed: [task, ...completed]),
    };
  }

  /// Executes the two-stage pull cascade across mutable queue lists in linear order.
  static void _cascadeQueues({
    required List<TaskItem> nextFocus,
    required List<TaskItem> nextReady,
    required List<TaskItem> nextPlanned,
  }) {
    var readyIndex = 0;
    var plannedIndex = 0;

    while (nextFocus.length < focusSoftLimit && readyIndex < nextReady.length) {
      nextFocus.add(nextReady[readyIndex].toActive());
      readyIndex++;
    }
    if (readyIndex > 0) {
      nextReady.removeRange(0, readyIndex);
    }

    while (nextReady.length < readySoftLimit &&
        plannedIndex < nextPlanned.length) {
      nextReady.add(nextPlanned[plannedIndex].toActive());
      plannedIndex++;
    }
    if (plannedIndex > 0) {
      nextPlanned.removeRange(0, plannedIndex);
    }

    var secondReadyIndex = 0;
    while (nextFocus.length < focusSoftLimit &&
        secondReadyIndex < nextReady.length) {
      nextFocus.add(nextReady[secondReadyIndex].toActive());
      secondReadyIndex++;
    }
    if (secondReadyIndex > 0) {
      nextReady.removeRange(0, secondReadyIndex);
    }

    var secondPlannedIndex = 0;
    while (nextReady.length < readySoftLimit &&
        secondPlannedIndex < nextPlanned.length) {
      nextReady.add(nextPlanned[secondPlannedIndex].toActive());
      secondPlannedIndex++;
    }
    if (secondPlannedIndex > 0) {
      nextPlanned.removeRange(0, secondPlannedIndex);
    }
  }

  /// Downgrades [task] from Tier 1 (`focus`) to Tier 2 (`ready`) after pulling replacements.
  TaskBoard _downgradeFromFocus(TaskItem task, DateTime now) {
    final nextFocus = _filterOutList(focus, task.id);
    final nextReady = List<TaskItem>.from(ready);
    final nextPlanned = List<TaskItem>.from(planned);

    var readyIndex = 0;
    while (nextFocus.length < focusSoftLimit && readyIndex < nextReady.length) {
      nextFocus.add(nextReady[readyIndex].toActive());
      readyIndex++;
    }
    if (readyIndex > 0) {
      nextReady.removeRange(0, readyIndex);
    }

    var plannedForFocusIndex = 0;
    while (nextFocus.length < focusSoftLimit &&
        plannedForFocusIndex < nextPlanned.length) {
      nextFocus.add(nextPlanned[plannedForFocusIndex].toActive());
      plannedForFocusIndex++;
    }
    if (plannedForFocusIndex > 0) {
      nextPlanned.removeRange(0, plannedForFocusIndex);
    }

    nextReady.add(task);

    var plannedIndex = 0;
    while (nextReady.length < readySoftLimit &&
        plannedIndex < nextPlanned.length) {
      nextReady.add(nextPlanned[plannedIndex].toActive());
      plannedIndex++;
    }
    if (plannedIndex > 0) {
      nextPlanned.removeRange(0, plannedIndex);
    }

    return copyWith(
      focus: nextFocus,
      ready: nextReady,
      planned: nextPlanned,
    ).pruneCompletedTasks(currentDate: now);
  }

  /// Downgrades [task] from Tier 2 (`ready`) to Tier 3 (`planned`) after pulling replacements.
  TaskBoard _downgradeFromReady(TaskItem task, DateTime now) {
    final nextFocus = List<TaskItem>.from(focus);
    final nextReady = _filterOutList(ready, task.id);
    final nextPlanned = List<TaskItem>.from(planned);

    _cascadeQueues(
      nextFocus: nextFocus,
      nextReady: nextReady,
      nextPlanned: nextPlanned,
    );
    nextPlanned.add(task);

    return copyWith(
      focus: nextFocus,
      ready: nextReady,
      planned: nextPlanned,
    ).pruneCompletedTasks(currentDate: now);
  }

  /// Returns a new list excluding the task with [taskId].
  static List<TaskItem> _filterOutList(List<TaskItem> list, String taskId) {
    return [
      for (final item in list)
        if (item.id != taskId) item,
    ];
  }

  /// Finds a task with [taskId] inside [list], or `null` if absent.
  static TaskItem? _findInList(List<TaskItem> list, String taskId) {
    for (final task in list) {
      if (task.id == taskId) {
        return task;
      }
    }
    return null;
  }

  /// Returns whether [task] is within the 30-day retention window relative to [normalizedNow].
  static bool _isWithinRetention(TaskItem task, DateTime normalizedNow) {
    final completedDate = task.completedAt;
    if (completedDate == null) {
      return true;
    }
    final normalizedTaskDate = DateTime.utc(
      completedDate.year,
      completedDate.month,
      completedDate.day,
    );
    return normalizedNow.difference(normalizedTaskDate).inDays <=
        completedRetentionDays;
  }

  /// Removes the task with [taskId] from [tier].
  TaskBoard _removeTaskFromTier(String taskId, TaskTier tier) {
    return switch (tier) {
      TaskTier.focus => copyWith(focus: _filterOutList(focus, taskId)),
      TaskTier.ready => copyWith(ready: _filterOutList(ready, taskId)),
      TaskTier.planned => copyWith(planned: _filterOutList(planned, taskId)),
      TaskTier.blocked => copyWith(blocked: _filterOutList(blocked, taskId)),
      TaskTier.someday => copyWith(someday: _filterOutList(someday, taskId)),
      TaskTier.completed => copyWith(
        completed: _filterOutList(completed, taskId),
      ),
    };
  }

  /// Returns a new list with the task matching [taskId] renamed to [newTitle].
  static List<TaskItem> _renameInList(
    List<TaskItem> list,
    String taskId,
    String newTitle,
  ) {
    return [
      for (final item in list)
        item.id == taskId ? item.copyWith(title: newTitle) : item,
    ];
  }
}
