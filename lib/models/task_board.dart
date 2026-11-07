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
import 'task_board_mutator.dart';
import 'task_board_queue_mutator.dart';
import 'task_item.dart';
import 'task_tier.dart';
import 'tdf_metadata.dart';
import 'tdf_sync_metadata.dart';
import 'tdf_timezone.dart';

/// Immutable domain model representing the TierTask board across all 6 derived tiers (`1` to `6`).
@immutable
class TaskBoard {
  /// Creates an immutable [TaskBoard] with normalized task lists for tiers `1` to `6`.
  TaskBoard({
    List<TaskItem> focus = const [],
    List<TaskItem> ready = const [],
    List<TaskItem> planned = const [],
    List<TaskItem> blocked = const [],
    List<TaskItem> someday = const [],
    List<TaskItem> completed = const [],
    List<TdfLabel> labels = const [],
    TdfDeletedBlock? deletedBlock,
    TdfQueueBlock? queueBlock,
  }) : this._normalized(
         TaskBoardEvaluator.normalizeTierSlices(
           focus: focus,
           ready: ready,
           planned: planned,
           blocked: blocked,
           someday: someday,
           completed: completed,
           labels: labels,
           deletedBlock: deletedBlock ?? TdfDeletedBlock.empty,
           explicitQueueBlock: queueBlock,
         ),
       );

  /// Creates an immutable [TaskBoard] from pre-normalized [slices].
  TaskBoard._normalized(NormalizedTierSlices slices)
    : focus = List<TaskItem>.unmodifiable(slices.focus),
      ready = List<TaskItem>.unmodifiable(slices.ready),
      planned = List<TaskItem>.unmodifiable(slices.planned),
      blocked = List<TaskItem>.unmodifiable(slices.blocked),
      someday = List<TaskItem>.unmodifiable(slices.someday),
      completed = List<TaskItem>.unmodifiable(slices.completed),
      labels = List<TdfLabel>.unmodifiable(slices.labels),
      deletedBlock = slices.deletedBlock,
      queueBlock = slices.queueBlock,
      openTaskCountsByLabel = Map.unmodifiable(slices.openTaskCountsByLabel),
      sortedLabels = TaskBoardEvaluator.sortLabelsAlphabetically(slices.labels);

  /// Creates an empty [TaskBoard] across all 6 tiers.
  factory TaskBoard.empty() => TaskBoard();

  /// Derives the 6 operational tiers from [tasks] in a single $O(N)$ pass per `TDF_SPEC.md` Section 5.
  factory TaskBoard.evaluate({
    required Iterable<TaskItem> tasks,
    DateTime? evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    List<TdfLabel> labels = const [],
    TdfDeletedBlock? deletedBlock,
    TdfQueueBlock? queueBlock,
    String? activeLabelId,
    double? currentLatitude,
    double? currentLongitude,
    bool pruneExpiredCompleted = false,
  }) => TaskBoard._normalized(
    TaskBoardEvaluator.evaluate(
      tasks: tasks,
      evaluationTime: evaluationTime,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      labels: labels,
      deletedBlock: deletedBlock,
      queueBlock: queueBlock,
      activeLabelId: activeLabelId,
      currentLatitude: currentLatitude,
      currentLongitude: currentLongitude,
      pruneExpiredCompleted: pruneExpiredCompleted,
    ),
  );

  /// Retention period in days for completed tasks in Tier 6 (`Completed`) and deletion records.
  static const int completedRetentionDays =
      TaskBoardEvaluator.completedRetentionDays;

  /// Retention period in seconds (`30 * 86,400 = 2,592,000` seconds) per `TDF_SPEC.md` Section 6.8.
  static const int completedRetentionSeconds =
      TaskBoardEvaluator.completedRetentionSeconds;

  /// Soft WIP limit for Tier 1 (`Focus`).
  static const int focusSoftLimit = TaskBoardEvaluator.focusSoftLimit;

  /// Soft WIP limit for Tier 2 (`Ready`).
  static const int readySoftLimit = TaskBoardEvaluator.readySoftLimit;

  /// Tier 4 (`Blocked`) task items.
  final List<TaskItem> blocked;

  /// Tier 6 (`Completed`) task items.
  final List<TaskItem> completed;

  /// Root `deleted` block storing deletion history generation and active task/label deletion records.
  final TdfDeletedBlock deletedBlock;

  /// Tier 1 (`Focus`) task items.
  final List<TaskItem> focus;

  /// Defined TDF `label` blocks in declaration order.
  final List<TdfLabel> labels;

  /// Precomputed map of open (non-completed) task counts across tiers `1` to `5` keyed by label ID.
  final Map<String, int> openTaskCountsByLabel;

  /// Tier 3 (`Planned`) task items.
  final List<TaskItem> planned;

  /// Root `queue` block storing the shared queue modification timestamp and ordered scheduled open task IDs.
  final TdfQueueBlock queueBlock;

  /// Tier 2 (`Ready`) task items.
  final List<TaskItem> ready;

  /// Tier 5 (`Someday`) task items.
  final List<TaskItem> someday;

  /// Defined TDF `label` blocks sorted alphabetically by display name.
  final List<TdfLabel> sortedLabels;

  /// Returns all tasks across all 6 tiers in canonical document order.
  List<TaskItem> get allTasks => _slices.allTasks;

  /// UTC timestamp of the last shared queue order modification (`queue.modified`).
  DateTime get queueModifiedAt => queueBlock.modifiedAt;

  /// Ordered list of scheduled open task IDs in the shared `queue` block.
  List<String> get queueTaskIds => queueBlock.taskIds;

  /// Normalized slice record view of this board.
  NormalizedTierSlices get _slices => (
    focus: focus,
    ready: ready,
    planned: planned,
    blocked: blocked,
    someday: someday,
    completed: completed,
    labels: labels,
    deletedBlock: deletedBlock,
    openTaskCountsByLabel: openTaskCountsByLabel,
    queueBlock: queueBlock,
  );

  /// Adds a new TDF `label` block with a unique identifier and optional `#RRGGBB` [color].
  TaskBoard addLabel(
    String name, {
    String? color,
    String? id,
    String? note,
    DateTime? currentDate,
    DateTime? modifiedAt,
    List<TaskCondition> conditions = const [],
  }) => _mutate(
    (slices) => TaskBoardMutator.addLabel(
      slices,
      name,
      color: color,
      id: id,
      note: note,
      currentDate: currentDate,
      modifiedAt: modifiedAt,
      conditions: conditions,
    ),
  );

  /// Adds a new task per `TDF_SPEC.md` Section 6.1, prunes expired completed tasks, and evaluates tiers.
  TaskBoard addTask(
    String title, {
    TaskTier targetTier = TaskTier.planned,
    bool isPriority = false,
    bool subtasksAutoFinish = false,
    List<SubtaskItem> subtasks = const [],
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    DateTime? modifiedAt,
    String? id,
    String? note,
    List<String> labelIds = const [],
    DateTime? suspendedAt,
    bool? isSuspendedForever,
    TaskRepeatRule? repeatRule,
    List<String> blockedByTaskIds = const [],
    List<TdfTaskDependency>? dependencies,
    List<TaskLink> links = const [],
    List<TaskCondition> conditions = const [],
  }) => _mutate(
    (slices) => TaskBoardMutator.addTask(
      slices,
      title,
      id: id,
      currentDate: currentDate,
      mutate: (taskId, now) => TaskBoardMutator.updateTask(
        slices,
        taskId,
        title: title,
        note: note,
        targetTier: targetTier,
        isPriority: isPriority,
        subtasksAutoFinish: subtasksAutoFinish,
        subtasks: subtasks,
        labelIds: labelIds,
        suspendedAt: suspendedAt,
        isSuspendedForever: isSuspendedForever,
        repeatRule: repeatRule,
        blockedByTaskIds: blockedByTaskIds,
        dependencies: dependencies,
        links: links,
        conditions: conditions,
        currentDate: now,
        localEvaluationTime: localEvaluationTime,
        timeZone: timeZone,
        modifiedAt: modifiedAt,
        isNewTask: true,
      ),
    ),
  );

  /// Evaluates the active pull cycle and unblocks any tasks whose prerequisites or deferrals cleared.
  TaskBoard applyAutoPull({
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  }) => _mutate(
    (slices) => TaskBoardEvaluator.reevaluateBoard(
      slices,
      now: TaskItem.normalizeTimestamp(currentDate ?? DateTime.now().toUtc()),
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      pruneExpiredCompleted: false,
    ),
  );

  /// Moves an active task immediately to Tier 4 (`Blocked`) and refills vacated active slots.
  TaskBoard blockTask(
    String taskId, {
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    DateTime? suspendedUntil,
  }) => _mutate(
    (slices) => TaskBoardQueueMutator.blockTask(
      slices,
      taskId,
      currentDate: currentDate,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      suspendedUntil: suspendedUntil,
    ),
  );

  /// Removes expired deletion records (`now - deletedAt > 2,592,000` seconds) and increments `deletedBlock.generation`.
  TaskBoard cleanupExpiredDeletions({DateTime? currentDate}) => _mutate(
    (slices) => TaskBoardEvaluator.cleanupExpiredDeletions(
      slices,
      currentDate: currentDate,
    ),
  );

  /// Marks an active task as done per `TDF_SPEC.md` Sections 6.4 and 6.9.4.
  TaskBoard completeTask(
    String taskId, {
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    int? expectedCompletions,
  }) => _mutate(
    (slices) => TaskBoardMutator.completeTask(
      slices,
      taskId,
      currentDate: currentDate,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      expectedCompletions: expectedCompletions,
    ),
  );

  /// Returns a copy of this [TaskBoard] with the specified collections replaced.
  TaskBoard copyWith({
    List<TaskItem>? focus,
    List<TaskItem>? ready,
    List<TaskItem>? planned,
    List<TaskItem>? blocked,
    List<TaskItem>? someday,
    List<TaskItem>? completed,
    List<TdfLabel>? labels,
    TdfDeletedBlock? deletedBlock,
    TdfQueueBlock? queueBlock,
  }) {
    final nextFocus = focus ?? this.focus;
    final nextReady = ready ?? this.ready;
    final nextPlanned = planned ?? this.planned;
    final nextBlocked = blocked ?? this.blocked;
    final unqueuedBlocked = <String>{
      for (final task in this.blocked)
        if (!this.queueBlock.taskIds.contains(task.id)) task.id,
    };
    return TaskBoard(
      focus: nextFocus,
      ready: nextReady,
      planned: nextPlanned,
      blocked: nextBlocked,
      someday: someday ?? this.someday,
      completed: completed ?? this.completed,
      labels: labels ?? this.labels,
      deletedBlock: deletedBlock ?? this.deletedBlock,
      queueBlock:
          queueBlock ??
          TaskBoardQueueMutator.reconcileQueueWithSlices(
            currentQueue: this.queueBlock,
            focus: nextFocus,
            ready: nextReady,
            planned: nextPlanned,
            blocked: nextBlocked,
            previousUnqueuedBlockedIds: unqueuedBlocked,
          ),
    );
  }

  /// Deletes the label with [labelId], removes its reference from all tasks, and records the deletion in [deletedBlock].
  TaskBoard deleteLabel(String labelId, {DateTime? currentDate}) => _mutate(
    (slices) => TaskBoardMutator.deleteLabel(slices, labelId, currentDate),
  );

  /// Deletes the task with [taskId], removes its `queue` entry, and records the deletion in [deletedBlock].
  TaskBoard deleteTask(
    String taskId, {
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  }) => _mutate(
    (slices) => TaskBoardMutator.deleteTask(
      slices,
      taskId,
      currentDate: currentDate,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
    ),
  );

  /// Downgrades a task in `Focus` (to `Ready`), `Ready` (to `Planned`), or `Planned` (to `Someday`) per `TDF_SPEC.md` Section 6.3.
  TaskBoard downgradeTask(
    String taskId, {
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  }) => _mutate(
    (slices) => TaskBoardQueueMutator.downgradeTask(
      slices,
      taskId,
      currentDate: currentDate,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
    ),
  );

  /// Derives a filtered [TaskBoard] considering only tasks matching [activeLabelId] and optional GPS coordinates.
  TaskBoard evaluateForContext({
    String? activeLabelId,
    double? currentLatitude,
    double? currentLongitude,
    DateTime? evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  }) =>
      TaskBoard.evaluate(
        tasks: allTasks,
        evaluationTime: evaluationTime,
        localEvaluationTime: localEvaluationTime,
        timeZone: timeZone,
        labels: labels,
        deletedBlock: deletedBlock,
        queueBlock: queueBlock,
        activeLabelId: activeLabelId,
        currentLatitude: currentLatitude,
        currentLongitude: currentLongitude,
      ).logDomainMutation(
        'evaluateForContext activeLabel=${activeLabelId ?? "all"}',
      );

  /// Finds the [TdfLabel] with [labelId], or `null` if not found.
  TdfLabel? findLabel(String labelId) => _slices.findLabel(labelId);

  /// Finds the [TaskItem] with [taskId], or `null` if not found.
  TaskItem? findTask(String taskId) => _slices.findTask(taskId);

  /// Finds which [TaskTier] currently contains [taskId], or `null` if not found.
  TaskTier? findTierOfTask(String taskId) => _slices.findTierOfTask(taskId);

  /// Returns whether any label on the board (excluding [excludingLabelId]) already uses [name].
  bool hasDuplicateLabelName(String name, {String? excludingLabelId}) =>
      _slices.hasDuplicateLabelName(name, excludingLabelId: excludingLabelId);

  /// Returns whether any task on the board (excluding [excludingTaskId]) already uses [title].
  bool hasDuplicateTaskTitle(String title, {String? excludingTaskId}) =>
      _slices.hasDuplicateTaskTitle(title, excludingTaskId: excludingTaskId);

  /// Logs [action] with the resulting 6-tier task distribution under `LogTag.domain` and returns `this`.
  TaskBoard logDomainMutation(String action) {
    _slices.logDomainMutation(action);
    return this;
  }

  /// Moves [taskId] within [queueBlock] before [beforeTaskId], after [afterTaskId], or to the end per `TDF_SPEC.md` Section 6.11.1.
  TaskBoard moveTaskInQueue(
    String taskId, {
    String? beforeTaskId,
    String? afterTaskId,
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  }) => _mutate(
    (slices) => TaskBoardQueueMutator.moveTaskInQueue(
      slices,
      taskId,
      beforeTaskId: beforeTaskId,
      afterTaskId: afterTaskId,
      currentDate: currentDate,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
    ),
  );

  /// Returns the precomputed count of open (non-completed) tasks across tiers `1` to `5` referencing [labelId].
  int openTaskCountForLabel(String labelId) =>
      openTaskCountsByLabel[labelId] ?? 0;

  /// Prunes tasks in Tier 6 (`Completed`) older than 30 days (`2,592,000` seconds UTC) per `TDF_SPEC.md` Sections 5.2 and 6.8.1.
  TaskBoard pruneCompletedTasks({DateTime? currentDate}) => _mutate(
    (slices) => TaskBoardEvaluator.pruneCompletedTasks(
      slices,
      currentDate: currentDate,
    ),
  );

  /// Restores a completed task back into `Someday`, `Planned`, or `Focus` per `TDF_SPEC.md` Section 6.5.
  TaskBoard restoreTask(
    String taskId, {
    TaskTier targetTier = TaskTier.planned,
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  }) => _mutate(
    (slices) => TaskBoardQueueMutator.restoreTask(
      slices,
      taskId,
      targetTier: targetTier,
      currentDate: currentDate,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
    ),
  );

  /// Schedules a task from `Someday` into the active pull cycle per `TDF_SPEC.md` Section 6.2.
  TaskBoard scheduleTask(
    String taskId, {
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    bool isPriority = false,
  }) => _mutate(
    (slices) => TaskBoardQueueMutator.scheduleTask(
      slices,
      taskId,
      currentDate: currentDate,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      isPriority: isPriority,
    ),
  );

  /// Returns the task list for a given [tier].
  List<TaskItem> tasksForTier(TaskTier tier) => _slices.tasksForTier(tier);

  /// Toggles the subtask step at [stepIndex] on [taskId], auto-completing the task when `subtasks auto-finish` is enabled.
  TaskBoard toggleSubtask(
    String taskId,
    int stepIndex, {
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  }) => _mutate(
    (slices) => TaskBoardMutator.toggleSubtask(
      slices,
      taskId,
      stepIndex,
      currentDate: currentDate,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
    ),
  );

  /// Updates an existing label with [labelId], re-evaluates the 6-tier pipeline, and ignores empty or duplicate label names.
  TaskBoard updateLabel(
    String labelId, {
    String? name,
    String? color,
    bool clearColor = false,
    String? note,
    bool clearNote = false,
    List<TaskCondition>? conditions,
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  }) => _mutate(
    (slices) => TaskBoardMutator.updateLabel(
      slices,
      labelId,
      name: name,
      color: color,
      clearColor: clearColor,
      note: note,
      clearNote: clearNote,
      conditions: conditions,
      currentDate: currentDate,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
    ),
  );

  /// Updates an existing task with [taskId], re-evaluates the 6-tier pipeline, and ignores empty or duplicate task titles.
  TaskBoard updateTask(
    String taskId, {
    String? title,
    String? note,
    TaskTier? targetTier,
    bool? isPriority,
    bool? subtasksAutoFinish,
    List<SubtaskItem>? subtasks,
    List<String>? labelIds,
    DateTime? suspendedAt,
    bool? isSuspendedForever,
    bool clearSuspendedAt = false,
    TaskRepeatRule? repeatRule,
    bool clearRepeatRule = false,
    List<String>? blockedByTaskIds,
    List<TdfTaskDependency>? dependencies,
    List<TaskLink>? links,
    List<TaskCondition>? conditions,
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  }) => _mutate(
    (slices) => TaskBoardMutator.updateTask(
      slices,
      taskId,
      title: title,
      note: note,
      targetTier: targetTier,
      isPriority: isPriority,
      subtasksAutoFinish: subtasksAutoFinish,
      subtasks: subtasks,
      labelIds: labelIds,
      suspendedAt: suspendedAt,
      isSuspendedForever: isSuspendedForever,
      clearSuspendedAt: clearSuspendedAt,
      repeatRule: repeatRule,
      clearRepeatRule: clearRepeatRule,
      blockedByTaskIds: blockedByTaskIds,
      dependencies: dependencies,
      links: links,
      conditions: conditions,
      currentDate: currentDate,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
    ),
  );

  /// Returns whether adding [candidateBlockerId] as a prerequisite of [taskId] would create a dependency cycle.
  bool wouldCreateDependencyCycle(String taskId, String candidateBlockerId) =>
      TaskBoardEvaluator.wouldCreateDependencyCycle(
        _slices,
        taskId,
        candidateBlockerId,
      );

  /// Applies [mutate] to `_slices` and returns `this` when the slices are unchanged.
  TaskBoard _mutate(
    NormalizedTierSlices Function(NormalizedTierSlices slices) mutate,
  ) {
    final current = _slices;
    final next = mutate(current);
    return identical(current, next) ? this : TaskBoard._normalized(next);
  }
}
