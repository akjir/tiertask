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
         _normalizeTierSlices(
           focus: focus,
           ready: ready,
           planned: planned,
           blocked: blocked,
           someday: someday,
           completed: completed,
           labels: labels,
           explicitQueueBlock: queueBlock,
         ),
         labels: labels,
         deletedBlock: deletedBlock ?? TdfDeletedBlock.empty,
       );

  TaskBoard._normalized(
    _NormalizedTierSlices slices, {
    required List<TdfLabel> labels,
    required this.deletedBlock,
  }) : focus = List<TaskItem>.unmodifiable(slices.focus),
       ready = List<TaskItem>.unmodifiable(slices.ready),
       planned = List<TaskItem>.unmodifiable(slices.planned),
       blocked = List<TaskItem>.unmodifiable(slices.blocked),
       someday = List<TaskItem>.unmodifiable(slices.someday),
       completed = List<TaskItem>.unmodifiable(slices.completed),
       labels = List<TdfLabel>.unmodifiable(labels),
       queueBlock = slices.queueBlock,
       openTaskCountsByLabel = Map<String, int>.unmodifiable(
         slices.openTaskCountsByLabel,
       ),
       sortedLabels = _sortLabelsAlphabetically(labels);

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
  }) {
    final now = TaskItem.normalizeTimestamp(
      evaluationTime ?? DateTime.now().toUtc(),
    );
    final localNow = (timeZone != null && timeZone.isAvailable)
        ? timeZone.toLocalWallClock(now)
        : _resolveLocalEvaluationTime(evaluationTime, localEvaluationTime);
    final taskList = List<TaskItem>.from(tasks);
    final taskMap = <String, TaskItem>{
      for (final task in taskList) task.id: task,
    };
    final labelMap = <String, TdfLabel>{
      for (final label in labels) label.id: label,
    };

    final completedList = <TaskItem>[];
    final somedayList = <TaskItem>[];
    final blockedList = <TaskItem>[];
    final eligibleById = <String, TaskItem>{};
    final prunedTaskRecords = <TdfDeletedTaskRecord>[];

    for (var i = 0; i < taskList.length; i++) {
      _classifyTaskIntoPipeline(
        task: taskList[i],
        nowUtc: now,
        localNow: localNow,
        taskMap: taskMap,
        labelMap: labelMap,
        activeLabelId: activeLabelId,
        currentLatitude: currentLatitude,
        currentLongitude: currentLongitude,
        pruneExpiredCompleted: pruneExpiredCompleted,
        completedList: completedList,
        somedayList: somedayList,
        blockedList: blockedList,
        eligibleById: eligibleById,
        prunedTaskRecords: prunedTaskRecords,
      );
    }

    final resolvedDeletedBlock = _mergePrunedTasksIntoDeletedBlock(
      deletedBlock ?? TdfDeletedBlock.empty,
      prunedTaskRecords,
    );
    final resolvedQueueBlock = queueBlock ?? _deriveDefaultQueueBlock(taskList);

    final orderedEligible = _orderEligibleByQueue(
      eligibleById: eligibleById,
      queueTaskIds: resolvedQueueBlock.taskIds,
    );
    final focusList = <TaskItem>[];
    final readyList = <TaskItem>[];
    final plannedList = <TaskItem>[];
    _sliceEligibleTasks(
      orderedEligible,
      focusList: focusList,
      readyList: readyList,
      plannedList: plannedList,
    );

    return TaskBoard(
      focus: focusList,
      ready: readyList,
      planned: plannedList,
      blocked: blockedList,
      someday: somedayList,
      completed: completedList,
      labels: labels,
      deletedBlock: resolvedDeletedBlock,
      queueBlock: resolvedQueueBlock,
    );
  }

  /// Retention period in days for completed tasks in Tier 6 (`Completed`) and deletion records.
  static const int completedRetentionDays = 30;

  /// Retention period in seconds (`30 * 86,400 = 2,592,000` seconds) per `TDF_SPEC.md` Section 6.8.
  static const int completedRetentionSeconds = 2592000;

  /// Soft WIP limit for Tier 1 (`Focus`).
  static const int focusSoftLimit = 3;

  /// Soft WIP limit for Tier 2 (`Ready`).
  static const int readySoftLimit = 5;

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
  List<TaskItem> get allTasks => List<TaskItem>.unmodifiable([
    ...focus,
    ...ready,
    ...planned,
    ...blocked,
    ...someday,
    ...completed,
  ]);

  /// UTC timestamp of the last shared queue order modification (`queue.modified`).
  DateTime get queueModifiedAt => queueBlock.modifiedAt;

  /// Ordered list of scheduled open task IDs in the shared `queue` block.
  List<String> get queueTaskIds => queueBlock.taskIds;

  /// Adds a new TDF `label` block with a unique identifier and optional `#RRGGBB` [color].
  TaskBoard addLabel(
    String name, {
    String? color,
    String? id,
    String? note,
    DateTime? currentDate,
    DateTime? modifiedAt,
    List<TaskCondition> conditions = const [],
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return this;
    }
    final existingIds = _collectAllUsedEntityIds();
    final resolvedModifiedAt = modifiedAt != null
        ? TaskItem.normalizeTimestamp(modifiedAt)
        : (currentDate != null
              ? TaskItem.normalizeTimestamp(currentDate)
              : null);
    final trimmedId = id?.trim();
    final labelId = (trimmedId != null && trimmedId.isNotEmpty)
        ? trimmedId
        : generateLabelId(
            timestamp: resolvedModifiedAt,
            existingIds: existingIds,
          );
    if (labels.any((label) => label.id == labelId) ||
        deletedBlock.findLabelRecord(labelId) != null) {
      return this;
    }
    final normalizedColor = TdfColor.normalizeHex(color);
    final trimmedNote = note?.trim();
    final effectiveNote = (trimmedNote != null && trimmedNote.isNotEmpty)
        ? trimmedNote
        : null;
    final newLabel = TdfLabel(
      id: labelId,
      name: trimmed,
      color: normalizedColor,
      note: effectiveNote,
      modifiedAt: resolvedModifiedAt,
      conditions: _sanitizeLabelConditions(conditions),
    );
    return copyWith(labels: [...labels, newLabel])
        ._logDomainMutation('addLabel id=$labelId name="$trimmed"');
  }

  /// Adds a new task per `TDF_SPEC.md` Section 6.1, prunes expired completed tasks,
  /// and runs the dynamic 6-tier derivation pipeline.
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
  }) {
    final trimmed = title.trim();
    if (trimmed.isEmpty || hasDuplicateTaskTitle(trimmed)) {
      return this;
    }

    final now = TaskItem.normalizeTimestamp(
      currentDate ?? DateTime.now().toUtc(),
    );
    final localNow = _resolveLocalEvaluationTime(
      currentDate,
      localEvaluationTime,
    );
    final resolvedTimeZone = _resolveEffectiveTimeZone(
      now: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
    );
    final trimmedNote = note?.trim();
    final effectiveNote = (trimmedNote != null && trimmedNote.isNotEmpty)
        ? trimmedNote
        : null;
    final effectivePriority = isPriority || targetTier == TaskTier.focus;
    final cleanSubtasks = _cleanSubtasks(subtasks);
    final autoCompleted =
        subtasksAutoFinish &&
        cleanSubtasks.isNotEmpty &&
        cleanSubtasks.every((step) => step.isCompleted);
    final isRecurringAutoCompletion =
        autoCompleted && targetTier != TaskTier.completed && repeatRule != null;
    final isDone =
        targetTier == TaskTier.completed ||
        (autoCompleted && !isRecurringAutoCompletion);
    final effectiveSubtasks = isDone
        ? _setAllSubtasksCompleted(cleanSubtasks, isCompleted: true)
        : cleanSubtasks;
    final isBlockedTarget = targetTier == TaskTier.blocked && !isDone;
    final resolvedForever =
        !isDone &&
        (isSuspendedForever ??
            (suspendedAt == TaskItem.defaultSuspendedAt ||
                (isBlockedTarget && suspendedAt == null)));
    final effectiveSuspendedAt = (isDone || resolvedForever)
        ? null
        : suspendedAt;
    final isActivelySuspended =
        resolvedForever ||
        (effectiveSuspendedAt != null && effectiveSuspendedAt.isAfter(now));
    final isSomeday =
        targetTier == TaskTier.someday && !isDone && !isActivelySuspended;
    final existingIds = _collectAllUsedEntityIds();
    final taskId =
        id ?? generateTaskId(timestamp: now, existingIds: existingIds);
    final armedDependencies = _armDependenciesForTask(
      taskId: taskId,
      candidateBlockedByIds: blockedByTaskIds,
      explicitDependencies: dependencies,
      existingDependencies: const [],
    );
    final cleanLinks = _cleanLinks(links);
    final cleanConditions = _sanitizeTaskConditions(conditions);
    final resolvedModifiedAt = modifiedAt != null
        ? TaskItem.normalizeTimestamp(modifiedAt)
        : now;

    final baseTask = TaskItem(
      id: taskId,
      title: trimmed,
      note: effectiveNote,
      isCompleted: isDone,
      completions: isDone ? 1 : 0,
      isPriority:
          effectivePriority &&
          !isSomeday &&
          (!isBlockedTarget || isActivelySuspended || repeatRule != null),
      createdAt: now,
      queuedAt: isSomeday ? null : now,
      completedAt: isDone ? now : null,
      modifiedAt: resolvedModifiedAt,
      suspendedAt: effectiveSuspendedAt,
      isSuspendedForever: resolvedForever,
      repeatRule: repeatRule,
      dependencies: armedDependencies,
      labelIds: labelIds,
      links: cleanLinks,
      conditions: cleanConditions,
      subtasksAutoFinish: subtasksAutoFinish,
      subtasks: effectiveSubtasks,
    );
    final newTask = isRecurringAutoCompletion
        ? _rescheduleRecurringTask(
            baseTask,
            repeatRule,
            now,
            resolvedTimeZone,
            preserveModifiedAt: resolvedModifiedAt,
          )
        : baseTask;

    if (isDone) {
      return copyWith(completed: [newTask, ...completed])
          .pruneCompletedTasks(currentDate: now)
          .applyAutoPull(
            currentDate: now,
            localEvaluationTime: localNow,
            timeZone: timeZone,
          )
          ._logDomainMutation('addTask id=$taskId title="$trimmed"');
    }

    final nextQueueBlock = newTask.queuedAt != null
        ? _appendTaskToQueue(queueBlock, newTask.id, now)
        : queueBlock;

    return TaskBoard.evaluate(
      tasks: [...allTasks, newTask],
      evaluationTime: now,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      labels: labels,
      deletedBlock: deletedBlock,
      queueBlock: nextQueueBlock,
      pruneExpiredCompleted: true,
    )._logDomainMutation('addTask id=$taskId title="$trimmed"');
  }

  /// Evaluates the active pull cycle and unblocks any tasks whose prerequisites or deferrals cleared.
  TaskBoard applyAutoPull({
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  }) {
    final now = TaskItem.normalizeTimestamp(
      currentDate ?? DateTime.now().toUtc(),
    );
    final localNow = (timeZone != null && timeZone.isAvailable)
        ? timeZone.toLocalWallClock(now)
        : _resolveLocalEvaluationTime(currentDate, localEvaluationTime);
    final taskList = allTasks;
    final taskMap = <String, TaskItem>{
      for (final task in taskList) task.id: task,
    };
    final labelMap = <String, TdfLabel>{
      for (final label in labels) label.id: label,
    };
    final normalizedTasks = <TaskItem>[];
    var nextQueueBlock = queueBlock;

    for (final task in taskList) {
      if (!task.isCompleted &&
          task.completedAt == null &&
          task.queuedAt == null &&
          findTierOfTask(task.id) == TaskTier.blocked &&
          !_isTaskBlocked(
            task: task,
            taskMap: taskMap,
            labelMap: labelMap,
            nowUtc: now,
            localNow: localNow,
            activeLabelId: null,
            currentLatitude: null,
            currentLongitude: null,
          )) {
        final scheduledTask = task.copyWith(
          queuedAt: now,
          modifiedAt: TaskItem.nextModifiedTimestamp(
            now,
            task.effectiveModifiedAt,
          ),
        );
        normalizedTasks.add(scheduledTask);
        nextQueueBlock = _appendTaskToQueue(
          nextQueueBlock,
          scheduledTask.id,
          now,
        );
      } else {
        normalizedTasks.add(task);
      }
    }

    return TaskBoard.evaluate(
      tasks: normalizedTasks,
      evaluationTime: now,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      labels: labels,
      deletedBlock: deletedBlock,
      queueBlock: nextQueueBlock,
    );
  }

  /// Moves an active task immediately to Tier 4 (`Blocked`) and refills vacated active slots.
  TaskBoard blockTask(
    String taskId, {
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    DateTime? suspendedUntil,
  }) {
    final now = TaskItem.normalizeTimestamp(
      currentDate ?? DateTime.now().toUtc(),
    );
    final localNow = _resolveLocalEvaluationTime(
      currentDate,
      localEvaluationTime,
    );
    final sourceTier = findTierOfTask(taskId);
    if (sourceTier == null || sourceTier == TaskTier.blocked) {
      return this;
    }
    final task = findTask(taskId);
    if (task == null) {
      return this;
    }

    final wasCompleted = task.isCompleted || task.completedAt != null;
    final useForever =
        suspendedUntil == null || suspendedUntil == TaskItem.defaultSuspendedAt;
    final blockedTask = task.copyWith(
      isCompleted: false,
      clearCompletedAt: true,
      isPriority: false,
      queuedAt: task.queuedAt ?? now,
      suspendedAt: useForever ? null : suspendedUntil,
      clearSuspendedAt: useForever,
      isSuspendedForever: useForever,
      subtasks: wasCompleted
          ? _setAllSubtasksCompleted(task.subtasks, isCompleted: false)
          : task.subtasks,
      modifiedAt: TaskItem.nextModifiedTimestamp(now, task.effectiveModifiedAt),
    );
    final nextQueueBlock = _appendTaskToQueue(queueBlock, taskId, now);
    final updatedTasks = <TaskItem>[
      for (final item in allTasks) item.id == taskId ? blockedTask : item,
    ];

    return TaskBoard.evaluate(
      tasks: updatedTasks,
      evaluationTime: now,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      labels: labels,
      deletedBlock: deletedBlock,
      queueBlock: nextQueueBlock,
      pruneExpiredCompleted: true,
    )._logDomainMutation('blockTask id=$taskId');
  }

  /// Removes expired task and label deletion records (`now - deletedAt > 2,592,000` seconds)
  /// and increments `deletedBlock.generation` once when at least one record is removed per `TDF_SPEC.md` Section 6.8.3.
  TaskBoard cleanupExpiredDeletions({DateTime? currentDate}) {
    final now = TaskItem.normalizeTimestamp(
      currentDate ?? DateTime.now().toUtc(),
    );
    final retainedTasks = <TdfDeletedTaskRecord>[
      for (final record in deletedBlock.tasks)
        if (!_isTimestampExpired(record.deletedAt, now)) record,
    ];
    final retainedLabels = <TdfDeletedLabelRecord>[
      for (final record in deletedBlock.labels)
        if (!_isTimestampExpired(record.deletedAt, now)) record,
    ];
    final removedCount =
        (deletedBlock.tasks.length - retainedTasks.length) +
        (deletedBlock.labels.length - retainedLabels.length);
    if (removedCount == 0) {
      return this;
    }
    if (deletedBlock.generation >= TdfDeletedBlock.maxGeneration) {
      throw const FormatException('LimitExceeded');
    }
    final nextDeletedBlock = TdfDeletedBlock(
      generation: deletedBlock.generation + 1,
      tasks: retainedTasks,
      labels: retainedLabels,
    );
    AppLogger.info(
      LogTag.domain,
      'cleanupExpiredDeletions removed=$removedCount generation=${nextDeletedBlock.generation}',
    );
    return copyWith(deletedBlock: nextDeletedBlock);
  }

  /// Marks an active task as done per `TDF_SPEC.md` Section 6.4 and 6.9.4:
  /// 1. Standard tasks: increments `completions`, sets `finished` to [currentDate], removes from `queue`, and places in Tier 6 (`Completed`).
  /// 2. Recurring tasks (`repeat` present): increments `completions`, rearms prerequisites, and reschedules into Tier 4 (`Blocked`) with `priority`, UTC `queued`, UTC `suspended`, and reset `subtasks` while preserving `queue` position.
  /// 3. Prunes items in Tier 6 older than 30 days and refills Tier 1 and Tier 2.
  TaskBoard completeTask(
    String taskId, {
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    int? expectedCompletions,
  }) {
    final now = TaskItem.normalizeTimestamp(
      currentDate ?? DateTime.now().toUtc(),
    );
    final localNow = _resolveLocalEvaluationTime(
      currentDate,
      localEvaluationTime,
    );
    final sourceTier = findTierOfTask(taskId);
    if (sourceTier == null || sourceTier == TaskTier.completed) {
      return this;
    }
    final task = findTask(taskId);
    if (task == null) {
      return this;
    }
    if (expectedCompletions != null &&
        task.completions != expectedCompletions) {
      return this;
    }
    if (task.completions >= TdfTaskDependency.maxCompletions) {
      throw const FormatException('LimitExceeded');
    }

    if (task.repeatRule case final repeatRule?) {
      final resolvedTimeZone = _resolveEffectiveTimeZone(
        now: now,
        localEvaluationTime: localEvaluationTime,
        timeZone: timeZone,
      );
      final rescheduledTask = _rescheduleRecurringTask(
        task,
        repeatRule,
        now,
        resolvedTimeZone,
      );
      final nextQueueBlock = _appendTaskToQueue(queueBlock, taskId, now);
      final updatedTasks = <TaskItem>[
        for (final item in allTasks) item.id == taskId ? rescheduledTask : item,
      ];
      return TaskBoard.evaluate(
        tasks: updatedTasks,
        evaluationTime: now,
        localEvaluationTime: localNow,
        timeZone: timeZone,
        labels: labels,
        deletedBlock: deletedBlock,
        queueBlock: nextQueueBlock,
        pruneExpiredCompleted: true,
      )._logDomainMutation('completeTask (recurring) id=$taskId');
    }

    final completedTask = task.toCompleted(now);
    final nextQueueBlock = _removeTaskFromQueue(queueBlock, taskId, now);
    final updatedTasks = <TaskItem>[
      completedTask,
      for (final item in allTasks)
        if (item.id != taskId) item,
    ];

    return TaskBoard.evaluate(
      tasks: updatedTasks,
      evaluationTime: now,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      labels: labels,
      deletedBlock: deletedBlock,
      queueBlock: nextQueueBlock,
      pruneExpiredCompleted: true,
    )._logDomainMutation('completeTask id=$taskId');
  }

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
    final nextSomeday = someday ?? this.someday;
    final nextCompleted = completed ?? this.completed;
    final resolvedQueue =
        queueBlock ??
        _reconcileQueueWithSlices(
          currentQueue: this.queueBlock,
          focus: nextFocus,
          ready: nextReady,
          planned: nextPlanned,
          blocked: nextBlocked,
        );
    return TaskBoard(
      focus: nextFocus,
      ready: nextReady,
      planned: nextPlanned,
      blocked: nextBlocked,
      someday: nextSomeday,
      completed: nextCompleted,
      labels: labels ?? this.labels,
      deletedBlock: deletedBlock ?? this.deletedBlock,
      queueBlock: resolvedQueue,
    );
  }

  /// Deletes the label with [labelId], removes its reference from all tasks (advancing their `modified` timestamps),
  /// and records the deletion in [deletedBlock] per `TDF_SPEC.md` Section 6.8.1.
  TaskBoard deleteLabel(String labelId, {DateTime? currentDate}) {
    final existingLabel = findLabel(labelId);
    if (existingLabel == null) {
      return this;
    }
    final nextLabels = <TdfLabel>[
      for (final label in labels)
        if (label.id != labelId) label,
    ];
    final now = TaskItem.normalizeTimestamp(
      currentDate ?? DateTime.now().toUtc(),
    );
    final deletionRevision = TaskItem.nextModifiedTimestamp(
      now,
      existingLabel.effectiveModifiedAt,
    );
    final nextDeletedBlock = _recordLabelDeletion(
      deletedBlock,
      TdfDeletedLabelRecord(labelId: labelId, deletedAt: deletionRevision),
    );
    return copyWith(
      focus: _stripLabelFromTasks(focus, labelId, now),
      ready: _stripLabelFromTasks(ready, labelId, now),
      planned: _stripLabelFromTasks(planned, labelId, now),
      blocked: _stripLabelFromTasks(blocked, labelId, now),
      someday: _stripLabelFromTasks(someday, labelId, now),
      completed: _stripLabelFromTasks(completed, labelId, now),
      labels: nextLabels,
      deletedBlock: nextDeletedBlock,
    )._logDomainMutation('deleteLabel id=$labelId');
  }

  /// Deletes the task with [taskId], removes its `queue` entry, and records the deletion
  /// with its completion checkpoint in [deletedBlock] per `TDF_SPEC.md` Section 6.8.1.
  TaskBoard deleteTask(
    String taskId, {
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  }) {
    final existingTask = findTask(taskId);
    if (existingTask == null) {
      return this;
    }
    final now = TaskItem.normalizeTimestamp(
      currentDate ?? DateTime.now().toUtc(),
    );
    final localNow = _resolveLocalEvaluationTime(
      currentDate,
      localEvaluationTime,
    );
    final deletionRevision = TaskItem.nextModifiedTimestamp(
      now,
      existingTask.effectiveModifiedAt,
    );
    final nextDeletedBlock = _recordTaskDeletion(
      deletedBlock,
      TdfDeletedTaskRecord(
        taskId: taskId,
        deletedAt: deletionRevision,
        completionsCheckpoint: existingTask.completions,
      ),
    );
    final nextQueueBlock = _removeTaskFromQueue(queueBlock, taskId, now);
    final remainingTasks = <TaskItem>[
      for (final task in allTasks)
        if (task.id != taskId) task,
    ];
    return TaskBoard.evaluate(
      tasks: remainingTasks,
      evaluationTime: now,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      labels: labels,
      deletedBlock: nextDeletedBlock,
      queueBlock: nextQueueBlock,
      pruneExpiredCompleted: true,
    )._logDomainMutation('deleteTask id=$taskId');
  }

  /// Downgrades a task in `Focus` (to `Ready`), `Ready` (to `Planned`), or `Planned` (to `Someday`) per `TDF_SPEC.md` Section 6.3.
  TaskBoard downgradeTask(
    String taskId, {
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  }) {
    final now = TaskItem.normalizeTimestamp(
      currentDate ?? DateTime.now().toUtc(),
    );
    final localNow = _resolveLocalEvaluationTime(
      currentDate,
      localEvaluationTime,
    );
    final sourceTier = findTierOfTask(taskId);
    if (sourceTier == null) {
      return this;
    }
    final task = findTask(taskId);
    if (task == null) {
      return this;
    }

    if (sourceTier == TaskTier.focus) {
      return _downgradeFromFocus(
        task,
        now,
        localNow: localNow,
        timeZone: timeZone,
      )._logDomainMutation('downgradeTask id=$taskId from=Focus');
    }
    if (sourceTier == TaskTier.ready) {
      return _downgradeToPlanned(
        task,
        now,
        localNow: localNow,
        timeZone: timeZone,
      )._logDomainMutation('downgradeTask id=$taskId from=Ready');
    }
    if (sourceTier == TaskTier.planned) {
      return _downgradeToSomeday(
        task,
        now,
        localNow: localNow,
        timeZone: timeZone,
      )._logDomainMutation('downgradeTask id=$taskId from=Planned');
    }
    return this;
  }

  /// Derives a filtered [TaskBoard] considering only tasks matching [activeLabelId]
  /// and optional GPS coordinates while preserving all `TDF_SPEC.md` Section 5 rules.
  TaskBoard evaluateForContext({
    String? activeLabelId,
    double? currentLatitude,
    double? currentLongitude,
    DateTime? evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  }) {
    return TaskBoard.evaluate(
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
    )._logDomainMutation(
      'evaluateForContext activeLabel=${activeLabelId ?? "all"}',
    );
  }

  /// Finds the [TdfLabel] with [labelId], or `null` if not found.
  TdfLabel? findLabel(String labelId) {
    for (final label in labels) {
      if (label.id == labelId) {
        return label;
      }
    }
    return null;
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

  /// Returns whether any label on the board (excluding [excludingLabelId]) already uses [name].
  bool hasDuplicateLabelName(String name, {String? excludingLabelId}) {
    final normalized = name.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    for (final label in labels) {
      if (label.id != excludingLabelId &&
          label.name.trim().toLowerCase() == normalized) {
        return true;
      }
    }
    return false;
  }

  /// Returns whether any task on the board (excluding [excludingTaskId]) already uses [title].
  bool hasDuplicateTaskTitle(String title, {String? excludingTaskId}) {
    final normalized = title.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    for (final task in allTasks) {
      if (task.id != excludingTaskId &&
          task.title.trim().toLowerCase() == normalized) {
        return true;
      }
    }
    return false;
  }

  /// Moves [taskId] within [queueBlock] before [beforeTaskId], after [afterTaskId], or to the end per `TDF_SPEC.md` Section 6.11.1.
  TaskBoard moveTaskInQueue(
    String taskId, {
    String? beforeTaskId,
    String? afterTaskId,
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  }) {
    if (!queueBlock.taskIds.contains(taskId)) {
      return this;
    }
    if (beforeTaskId != null &&
        (beforeTaskId == taskId ||
            !queueBlock.taskIds.contains(beforeTaskId))) {
      return this;
    }
    if (afterTaskId != null &&
        (afterTaskId == taskId || !queueBlock.taskIds.contains(afterTaskId))) {
      return this;
    }
    final withoutTask = <String>[
      for (final id in queueBlock.taskIds)
        if (id != taskId) id,
    ];
    final nextIds = <String>[];
    if (beforeTaskId != null) {
      for (final id in withoutTask) {
        if (id == beforeTaskId) {
          nextIds.add(taskId);
        }
        nextIds.add(id);
      }
    } else if (afterTaskId != null) {
      for (final id in withoutTask) {
        nextIds.add(id);
        if (id == afterTaskId) {
          nextIds.add(taskId);
        }
      }
    } else {
      nextIds
        ..addAll(withoutTask)
        ..add(taskId);
    }
    if (listEquals(nextIds, queueBlock.taskIds)) {
      return this;
    }
    final now = TaskItem.normalizeTimestamp(
      currentDate ?? DateTime.now().toUtc(),
    );
    final localNow = _resolveLocalEvaluationTime(
      currentDate,
      localEvaluationTime,
    );
    final nextQueue = TdfQueueBlock(
      modifiedAt: TaskItem.nextModifiedTimestamp(now, queueBlock.modifiedAt),
      taskIds: nextIds,
    );
    return TaskBoard.evaluate(
      tasks: allTasks,
      evaluationTime: now,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      labels: labels,
      deletedBlock: deletedBlock,
      queueBlock: nextQueue,
    )._logDomainMutation('moveTaskInQueue id=$taskId');
  }

  /// Returns the precomputed count of open (non-completed) tasks across tiers `1` to `5` referencing [labelId].
  int openTaskCountForLabel(String labelId) =>
      openTaskCountsByLabel[labelId] ?? 0;

  /// Prunes tasks in Tier 6 (`Completed`) older than 30 days (`2,592,000` seconds UTC) per `TDF_SPEC.md` Sections 5.2 and 6.8.1,
  /// creating a deletion record in [deletedBlock] for each pruned task.
  TaskBoard pruneCompletedTasks({DateTime? currentDate}) {
    final now = TaskItem.normalizeTimestamp(
      currentDate ?? DateTime.now().toUtc(),
    );

    final retained = <TaskItem>[];
    final prunedRecords = <TdfDeletedTaskRecord>[];
    for (final task in completed) {
      if (_isWithinRetention(task, now)) {
        retained.add(task);
      } else {
        prunedRecords.add(
          TdfDeletedTaskRecord(
            taskId: task.id,
            deletedAt: TaskItem.nextModifiedTimestamp(
              now,
              task.effectiveModifiedAt,
            ),
            completionsCheckpoint: task.completions,
          ),
        );
      }
    }
    if (prunedRecords.isEmpty) {
      return this;
    }
    AppLogger.info(
      LogTag.domain,
      'pruneCompletedTasks pruned=${prunedRecords.length} expired tasks (>30 days)',
    );
    final nextDeletedBlock = _mergePrunedTasksIntoDeletedBlock(
      deletedBlock,
      prunedRecords,
    );
    return copyWith(completed: retained, deletedBlock: nextDeletedBlock);
  }

  /// Restores a completed task back into `Someday`, `Planned`, or `Focus` per `TDF_SPEC.md` Section 6.5.
  TaskBoard restoreTask(
    String taskId, {
    TaskTier targetTier = TaskTier.planned,
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  }) {
    if (targetTier == TaskTier.completed) {
      return this;
    }
    final now = TaskItem.normalizeTimestamp(
      currentDate ?? DateTime.now().toUtc(),
    );
    final localNow = _resolveLocalEvaluationTime(
      currentDate,
      localEvaluationTime,
    );
    final existing = findTask(taskId);
    if (existing == null ||
        (!existing.isCompleted && existing.completedAt == null)) {
      return this;
    }

    final isSomeday = targetTier == TaskTier.someday;
    final isFocus = targetTier == TaskTier.focus;
    final rearmedDependencies = _rearmDependencies(existing.dependencies);
    final restored = existing.copyWith(
      isCompleted: false,
      clearCompletedAt: true,
      clearSuspendedAt: true,
      isSuspendedForever: false,
      queuedAt: isSomeday ? null : now,
      clearQueuedAt: isSomeday,
      isPriority: isFocus,
      dependencies: rearmedDependencies,
      subtasks: _setAllSubtasksCompleted(existing.subtasks, isCompleted: false),
      modifiedAt: TaskItem.nextModifiedTimestamp(
        now,
        existing.effectiveModifiedAt,
      ),
    );
    final updatedTasks = <TaskItem>[
      for (final task in allTasks) task.id == taskId ? restored : task,
    ];
    final nextQueueBlock = isSomeday
        ? _removeTaskFromQueue(queueBlock, taskId, now)
        : _appendTaskToQueue(queueBlock, taskId, now);

    return TaskBoard.evaluate(
      tasks: updatedTasks,
      evaluationTime: now,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      labels: labels,
      deletedBlock: deletedBlock,
      queueBlock: nextQueueBlock,
      pruneExpiredCompleted: true,
    )._logDomainMutation(
      'restoreTask id=$taskId targetTier=${targetTier.name}',
    );
  }

  /// Schedules a task from `Someday` into the active pull cycle per `TDF_SPEC.md` Section 6.2.
  TaskBoard scheduleTask(
    String taskId, {
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    bool isPriority = false,
  }) {
    final now = TaskItem.normalizeTimestamp(
      currentDate ?? DateTime.now().toUtc(),
    );
    final localNow = _resolveLocalEvaluationTime(
      currentDate,
      localEvaluationTime,
    );
    final existing = findTask(taskId);
    if (existing == null) {
      return this;
    }

    final wasCompleted = existing.isCompleted || existing.completedAt != null;
    final rearmedDependencies = wasCompleted
        ? _rearmDependencies(existing.dependencies)
        : existing.dependencies;
    final scheduled = existing.copyWith(
      isCompleted: false,
      clearCompletedAt: true,
      clearSuspendedAt: wasCompleted,
      isSuspendedForever: wasCompleted ? false : existing.isSuspendedForever,
      queuedAt: now,
      isPriority: isPriority || existing.isPriority,
      dependencies: rearmedDependencies,
      subtasks: wasCompleted
          ? _setAllSubtasksCompleted(existing.subtasks, isCompleted: false)
          : existing.subtasks,
      modifiedAt: TaskItem.nextModifiedTimestamp(
        now,
        existing.effectiveModifiedAt,
      ),
    );
    final updatedTasks = <TaskItem>[
      for (final task in allTasks) task.id == taskId ? scheduled : task,
    ];
    final nextQueueBlock = _appendTaskToQueue(queueBlock, taskId, now);

    return TaskBoard.evaluate(
      tasks: updatedTasks,
      evaluationTime: now,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      labels: labels,
      deletedBlock: deletedBlock,
      queueBlock: nextQueueBlock,
      pruneExpiredCompleted: true,
    )._logDomainMutation('scheduleTask id=$taskId');
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

  /// Toggles the subtask step at [stepIndex] on [taskId], automatically completing
  /// the enclosing task when `subtasks auto-finish` is enabled and all steps are `true`.
  TaskBoard toggleSubtask(
    String taskId,
    int stepIndex, {
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  }) {
    final now = TaskItem.normalizeTimestamp(
      currentDate ?? DateTime.now().toUtc(),
    );
    final tier = findTierOfTask(taskId);
    final task = findTask(taskId);
    if (tier == null ||
        task == null ||
        tier == TaskTier.completed ||
        task.isCompleted ||
        task.completedAt != null) {
      return this;
    }
    if (stepIndex < 0 || stepIndex >= task.subtasks.length) {
      return this;
    }

    final updatedSubtasks = <SubtaskItem>[
      for (var i = 0; i < task.subtasks.length; i++)
        i == stepIndex
            ? task.subtasks[i].copyWith(
                isCompleted: !task.subtasks[i].isCompleted,
              )
            : task.subtasks[i],
    ];
    final allStepsDone =
        updatedSubtasks.isNotEmpty &&
        updatedSubtasks.every((step) => step.isCompleted);
    final willAutoComplete =
        task.subtasksAutoFinish && allStepsDone && tier != TaskTier.completed;
    final updatedTask = task.copyWith(
      subtasks: updatedSubtasks,
      modifiedAt: willAutoComplete
          ? task.modifiedAt
          : TaskItem.nextModifiedTimestamp(now, task.effectiveModifiedAt),
    );
    final replacedBoard = _replaceTaskInTier(tier, updatedTask);

    if (willAutoComplete) {
      return replacedBoard
          .completeTask(
            taskId,
            currentDate: now,
            localEvaluationTime: localEvaluationTime,
            timeZone: timeZone,
          )
          ._logDomainMutation(
            'toggleSubtask id=$taskId step=$stepIndex (auto-completed)',
          );
    }
    return replacedBoard._logDomainMutation(
      'toggleSubtask id=$taskId step=$stepIndex',
    );
  }

  /// Updates an existing label with [labelId], re-evaluates the 6-tier pipeline,
  /// and ignores empty or duplicate label names.
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
  }) {
    final existing = findLabel(labelId);
    if (existing == null) {
      return this;
    }
    final trimmedName = (name ?? existing.name).trim();
    if (trimmedName.isEmpty ||
        hasDuplicateLabelName(trimmedName, excludingLabelId: labelId)) {
      return this;
    }
    final now = TaskItem.normalizeTimestamp(
      currentDate ?? DateTime.now().toUtc(),
    );
    final localNow = _resolveLocalEvaluationTime(
      currentDate,
      localEvaluationTime,
    );
    final updatedLabel = _buildUpdatedLabel(
      existing: existing,
      name: trimmedName,
      color: color,
      clearColor: clearColor,
      note: note,
      clearNote: clearNote,
      conditions: conditions,
      now: now,
    );
    final nextLabels = <TdfLabel>[
      for (final label in labels) label.id == labelId ? updatedLabel : label,
    ];
    return TaskBoard.evaluate(
      tasks: allTasks,
      evaluationTime: now,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      labels: nextLabels,
      deletedBlock: deletedBlock,
      queueBlock: queueBlock,
      pruneExpiredCompleted: true,
    )._logDomainMutation(
      'updateLabel/renameLabel id=$labelId name="$trimmedName"',
    );
  }

  /// Updates an existing task with [taskId], re-evaluates the 6-tier pipeline,
  /// and ignores empty or duplicate task titles.
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
  }) {
    final existing = findTask(taskId);
    if (existing == null) {
      return this;
    }
    final trimmed = (title ?? existing.title).trim();
    if (trimmed.isEmpty ||
        hasDuplicateTaskTitle(trimmed, excludingTaskId: taskId)) {
      return this;
    }

    final now = TaskItem.normalizeTimestamp(
      currentDate ?? DateTime.now().toUtc(),
    );
    final localNow = _resolveLocalEvaluationTime(
      currentDate,
      localEvaluationTime,
    );
    final resolvedTimeZone = _resolveEffectiveTimeZone(
      now: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
    );
    final armedDependencies = (blockedByTaskIds != null || dependencies != null)
        ? _armDependenciesForTask(
            taskId: taskId,
            candidateBlockedByIds: blockedByTaskIds ?? const [],
            explicitDependencies: dependencies,
            existingDependencies: existing.dependencies,
          )
        : null;
    final sanitizedLinks = links != null ? _cleanLinks(links) : null;
    final sanitizedConditions = conditions != null
        ? _sanitizeTaskConditions(conditions)
        : null;
    final updatedTask = _buildUpdatedTask(
      existing: existing,
      title: trimmed,
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
      dependencies: armedDependencies,
      links: sanitizedLinks,
      conditions: sanitizedConditions,
      now: now,
      resolvedTimeZone: resolvedTimeZone,
    );
    final updatedTasks = <TaskItem>[
      for (final task in allTasks) task.id == taskId ? updatedTask : task,
    ];
    final nextQueueBlock = _updateQueueForEditedTask(
      currentQueue: queueBlock,
      existingTask: existing,
      updatedTask: updatedTask,
      now: now,
    );

    return TaskBoard.evaluate(
      tasks: updatedTasks,
      evaluationTime: now,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      labels: labels,
      deletedBlock: deletedBlock,
      queueBlock: nextQueueBlock,
      pruneExpiredCompleted: true,
    )._logDomainMutation('updateTask id=$taskId title="$trimmed"');
  }

  /// Returns whether adding [candidateBlockerId] as a prerequisite (`blocked`) of [taskId]
  /// would create a self-dependency or circular dependency in the task graph.
  bool wouldCreateDependencyCycle(String taskId, String candidateBlockerId) {
    final trimmedTaskId = taskId.trim();
    final trimmedBlockerId = candidateBlockerId.trim();
    if (trimmedTaskId.isEmpty || trimmedBlockerId.isEmpty) {
      return false;
    }
    if (trimmedTaskId == trimmedBlockerId) {
      return true;
    }
    final taskMap = <String, TaskItem>{
      for (final task in allTasks) task.id: task,
    };
    return _isReachableInDependencyGraph(
      startTaskId: trimmedBlockerId,
      targetTaskId: trimmedTaskId,
      taskMap: taskMap,
    );
  }

  /// Increments open task counters in [counts] for all [tasks] in a tier slice.
  static void _accumulateListLabelCounts(
    List<TaskItem> tasks,
    Map<String, int> counts,
  ) {
    for (final task in tasks) {
      _accumulateTaskLabelCounts(task, counts);
    }
  }

  /// Increments the open task counter in [counts] for each label ID referenced by [task].
  static void _accumulateTaskLabelCounts(
    TaskItem task,
    Map<String, int> counts,
  ) {
    for (final labelId in task.labelIds) {
      counts[labelId] = (counts[labelId] ?? 0) + 1;
    }
  }

  /// Appends [taskId] to [queue] if not already present, advancing `queue.modified` when changed.
  static TdfQueueBlock _appendTaskToQueue(
    TdfQueueBlock queue,
    String taskId,
    DateTime now,
  ) {
    if (queue.taskIds.contains(taskId)) {
      return queue;
    }
    if (queue.taskIds.length >= TdfQueueBlock.maxQueueEntries) {
      throw const FormatException('LimitExceeded');
    }
    return TdfQueueBlock(
      modifiedAt: TaskItem.nextModifiedTimestamp(now, queue.modifiedAt),
      taskIds: <String>[...queue.taskIds, taskId],
    );
  }

  /// Evaluates whether [task]'s effective condition groups are satisfied per `TDF_SPEC.md` Section 4.3.
  static bool _areTaskConditionsSatisfied({
    required TaskItem task,
    required Map<String, TdfLabel> labelMap,
    required DateTime evaluationTime,
    required String? activeLabelId,
    required double? currentLatitude,
    required double? currentLongitude,
  }) {
    if (_hasGlobalReset(task.conditions)) {
      return true;
    }
    if (task.labelIds.isEmpty) {
      return _evaluateRuleContext(
        baseRules: const [],
        taskRules: task.conditions,
        evaluationTime: evaluationTime,
        currentLatitude: currentLatitude,
        currentLongitude: currentLongitude,
      );
    }
    if (activeLabelId != null) {
      final activeLabel = labelMap[activeLabelId];
      return _evaluateRuleContext(
        baseRules: activeLabel?.conditions ?? const [],
        taskRules: task.conditions,
        evaluationTime: evaluationTime,
        currentLatitude: currentLatitude,
        currentLongitude: currentLongitude,
      );
    }
    for (final labelId in task.labelIds) {
      final label = labelMap[labelId];
      if (_evaluateRuleContext(
        baseRules: label?.conditions ?? const [],
        taskRules: task.conditions,
        evaluationTime: evaluationTime,
        currentLatitude: currentLatitude,
        currentLongitude: currentLongitude,
      )) {
        return true;
      }
    }
    return false;
  }

  /// Arms prerequisite requirements for [taskId] per `TDF_SPEC.md` Section 6.9.3:
  /// - Retains existing requirements for unchanged target IDs in [existingDependencies].
  /// - Captures `target.completions + 1` for newly added open prerequisites, `target.completions` for finished prerequisites, or `1` if missing.
  List<TdfTaskDependency> _armDependenciesForTask({
    required String taskId,
    required List<String> candidateBlockedByIds,
    required List<TdfTaskDependency>? explicitDependencies,
    required List<TdfTaskDependency> existingDependencies,
  }) {
    if (explicitDependencies != null) {
      final filtered = <TdfTaskDependency>[];
      final seen = <String>{};
      for (final dep in explicitDependencies) {
        final targetId = dep.taskId.trim();
        if (targetId.isEmpty ||
            !seen.add(targetId) ||
            wouldCreateDependencyCycle(taskId, targetId)) {
          continue;
        }
        filtered.add(dep);
      }
      return List<TdfTaskDependency>.unmodifiable(filtered);
    }

    final existingByTarget = <String, int>{
      for (final dep in existingDependencies)
        dep.taskId: dep.requiredCompletion,
    };
    final result = <TdfTaskDependency>[];
    final seen = <String>{};
    for (final rawBlockerId in candidateBlockedByIds) {
      final blockerId = rawBlockerId.trim();
      if (blockerId.isEmpty ||
          !seen.add(blockerId) ||
          wouldCreateDependencyCycle(taskId, blockerId)) {
        continue;
      }
      final existingRequired = existingByTarget[blockerId];
      final requiredCompletion =
          existingRequired ?? _captureRequirementForTarget(blockerId);
      result.add(
        TdfTaskDependency(
          taskId: blockerId,
          requiredCompletion: requiredCompletion,
        ),
      );
    }
    return List<TdfTaskDependency>.unmodifiable(result);
  }

  /// Builds an updated [TdfLabel] from [existing] with normalized color, note, and condition fields.
  static TdfLabel _buildUpdatedLabel({
    required TdfLabel existing,
    required String name,
    required String? color,
    required bool clearColor,
    required String? note,
    required bool clearNote,
    required List<TaskCondition>? conditions,
    required DateTime now,
  }) {
    final normalizedColor = TdfColor.normalizeHex(color);
    final shouldClearColor =
        clearColor || (color != null && normalizedColor == null);
    final trimmedNote = note?.trim();
    final shouldClearNote =
        clearNote || (trimmedNote != null && trimmedNote.isEmpty);
    final effectiveNote = (trimmedNote != null && trimmedNote.isNotEmpty)
        ? trimmedNote
        : null;
    final sanitizedConditions = conditions != null
        ? _sanitizeLabelConditions(conditions)
        : null;
    return existing.copyWith(
      name: name,
      color: normalizedColor,
      clearColor: shouldClearColor,
      note: effectiveNote,
      clearNote: shouldClearNote,
      conditions: sanitizedConditions,
      modifiedAt: TaskItem.nextModifiedTimestamp(
        now,
        existing.effectiveModifiedAt,
      ),
    );
  }

  /// Builds an updated [TaskItem] from [existing] with normalized scheduling and subtask fields.
  TaskItem _buildUpdatedTask({
    required TaskItem existing,
    required String title,
    required String? note,
    required TaskTier? targetTier,
    required bool? isPriority,
    required bool? subtasksAutoFinish,
    required List<SubtaskItem>? subtasks,
    required List<String>? labelIds,
    required DateTime? suspendedAt,
    required bool? isSuspendedForever,
    required bool clearSuspendedAt,
    required TaskRepeatRule? repeatRule,
    required bool clearRepeatRule,
    required List<TdfTaskDependency>? dependencies,
    required List<TaskLink>? links,
    required List<TaskCondition>? conditions,
    required DateTime now,
    required TdfTimeZoneContext resolvedTimeZone,
  }) {
    final wasCompleted = existing.isCompleted || existing.completedAt != null;
    final isRestoringCompleted =
        wasCompleted && targetTier != null && targetTier != TaskTier.completed;
    final effectiveAutoFinish =
        subtasksAutoFinish ?? existing.subtasksAutoFinish;
    final cleanSubtasks = subtasks != null
        ? _cleanSubtasks(subtasks)
        : existing.subtasks;
    final effectiveRepeatRule = clearRepeatRule
        ? null
        : (repeatRule ?? existing.repeatRule);
    final autoCompleted =
        !isRestoringCompleted &&
        effectiveAutoFinish &&
        cleanSubtasks.isNotEmpty &&
        cleanSubtasks.every((step) => step.isCompleted);
    final isRecurringAutoCompletion =
        autoCompleted &&
        targetTier != TaskTier.completed &&
        effectiveRepeatRule != null;
    final isDone =
        targetTier == TaskTier.completed ||
        (autoCompleted && !isRecurringAutoCompletion) ||
        (targetTier == null && wasCompleted);
    final effectiveSubtasks = isRestoringCompleted
        ? _setAllSubtasksCompleted(cleanSubtasks, isCompleted: false)
        : (isDone
              ? _setAllSubtasksCompleted(cleanSubtasks, isCompleted: true)
              : cleanSubtasks);
    final isBlockedTarget = !isDone && targetTier == TaskTier.blocked;
    final resolvedForever =
        !isDone &&
        !clearSuspendedAt &&
        !isRestoringCompleted &&
        (isSuspendedForever ??
            (suspendedAt == TaskItem.defaultSuspendedAt ||
                (suspendedAt == null &&
                    (existing.isSuspendedForever ||
                        (isBlockedTarget && existing.suspendedAt == null)))));
    final effectiveSuspendedAt =
        (isDone || clearSuspendedAt || isRestoringCompleted || resolvedForever)
        ? null
        : (suspendedAt ?? existing.suspendedAt);
    final isActivelySuspended =
        resolvedForever ||
        (effectiveSuspendedAt != null && effectiveSuspendedAt.isAfter(now));
    final isSomeday =
        !isDone &&
        !isActivelySuspended &&
        (targetTier == TaskTier.someday ||
            (targetTier == null && existing.queuedAt == null));
    final preservedPriority = isRestoringCompleted
        ? (isPriority ?? false)
        : (isPriority ?? existing.isPriority);
    final effectivePriority =
        !isSomeday &&
        (!isBlockedTarget ||
            isActivelySuspended ||
            effectiveRepeatRule != null) &&
        (preservedPriority || targetTier == TaskTier.focus);
    final hasFutureQueuedToReset =
        !isActivelySuspended &&
        existing.queuedAt != null &&
        existing.queuedAt!.isAfter(now);
    final effectiveQueuedAt = isSomeday
        ? null
        : ((isRestoringCompleted || hasFutureQueuedToReset)
              ? now
              : (existing.queuedAt ?? now));
    final trimmedNote = note?.trim();
    final baseDependencies = dependencies ?? existing.dependencies;
    final effectiveDependencies = isRestoringCompleted
        ? _rearmDependencies(baseDependencies)
        : baseDependencies;
    final nextCompletions = (isDone && !wasCompleted)
        ? existing.completions + 1
        : existing.completions;

    final baseUpdated = existing.copyWith(
      title: title,
      note: (trimmedNote != null && trimmedNote.isNotEmpty)
          ? trimmedNote
          : null,
      clearNote: trimmedNote != null && trimmedNote.isEmpty,
      isCompleted: isDone,
      completions: nextCompletions,
      completedAt: isDone ? (existing.completedAt ?? now) : null,
      clearCompletedAt: !isDone,
      isPriority: effectivePriority,
      queuedAt: effectiveQueuedAt,
      clearQueuedAt: isSomeday,
      suspendedAt: effectiveSuspendedAt,
      clearSuspendedAt: effectiveSuspendedAt == null,
      isSuspendedForever: resolvedForever,
      repeatRule: effectiveRepeatRule,
      clearRepeatRule: effectiveRepeatRule == null,
      dependencies: effectiveDependencies,
      labelIds: labelIds,
      links: links,
      conditions: conditions,
      subtasksAutoFinish: effectiveAutoFinish,
      subtasks: effectiveSubtasks,
      modifiedAt: TaskItem.nextModifiedTimestamp(
        now,
        existing.effectiveModifiedAt,
      ),
    );
    if (isRecurringAutoCompletion) {
      return _rescheduleRecurringTask(
        baseUpdated,
        effectiveRepeatRule,
        now,
        resolvedTimeZone,
        preserveModifiedAt: baseUpdated.modifiedAt,
      );
    }
    return baseUpdated;
  }

  /// Captures the required completion number for a newly added prerequisite [targetId] per `TDF_SPEC.md` Section 6.9.3.
  int _captureRequirementForTarget(String targetId) {
    final target = findTask(targetId);
    if (target == null) {
      return 1;
    }
    if (target.isCompleted || target.completedAt != null) {
      return target.completions >= 1 ? target.completions : 1;
    }
    if (target.completions >= TdfTaskDependency.maxCompletions) {
      throw const FormatException('LimitExceeded');
    }
    return target.completions + 1;
  }

  /// Classifies a single [task] into the Section 5 evaluation buckets.
  static void _classifyTaskIntoPipeline({
    required TaskItem task,
    required DateTime nowUtc,
    required DateTime localNow,
    required Map<String, TaskItem> taskMap,
    required Map<String, TdfLabel> labelMap,
    required String? activeLabelId,
    required double? currentLatitude,
    required double? currentLongitude,
    required bool pruneExpiredCompleted,
    required List<TaskItem> completedList,
    required List<TaskItem> somedayList,
    required List<TaskItem> blockedList,
    required Map<String, TaskItem> eligibleById,
    required List<TdfDeletedTaskRecord> prunedTaskRecords,
  }) {
    if (task.completedAt != null || task.isCompleted) {
      if (pruneExpiredCompleted && !_isWithinRetention(task, nowUtc)) {
        prunedTaskRecords.add(
          TdfDeletedTaskRecord(
            taskId: task.id,
            deletedAt: TaskItem.nextModifiedTimestamp(
              nowUtc,
              task.effectiveModifiedAt,
            ),
            completionsCheckpoint: task.completions,
          ),
        );
        return;
      }
      if (activeLabelId == null || task.labelIds.contains(activeLabelId)) {
        completedList.add(task.copyWith(isCompleted: true));
      }
      return;
    }

    if (activeLabelId != null && !task.labelIds.contains(activeLabelId)) {
      return;
    }

    if (_hasActiveDeferral(task, nowUtc)) {
      blockedList.add(task);
      return;
    }

    if (task.queuedAt == null) {
      somedayList.add(task);
      return;
    }

    if (_isTaskBlocked(
      task: task,
      taskMap: taskMap,
      labelMap: labelMap,
      nowUtc: nowUtc,
      localNow: localNow,
      activeLabelId: activeLabelId,
      currentLatitude: currentLatitude,
      currentLongitude: currentLongitude,
    )) {
      blockedList.add(task);
      return;
    }

    eligibleById[task.id] = task;
  }

  /// Trims, validates, and caps [links] at [TaskLink.maxLinksPerTask] while preserving order.
  static List<TaskLink> _cleanLinks(List<TaskLink> links) {
    final cleaned = <TaskLink>[];
    for (final link in links) {
      if (cleaned.length >= TaskLink.maxLinksPerTask) {
        break;
      }
      final parsed = TaskLink.tryParse(rawTitle: link.title, rawUri: link.uri);
      if (parsed != null) {
        cleaned.add(parsed);
      }
    }
    return cleaned;
  }

  /// Trims and filters out empty subtask entries.
  static List<SubtaskItem> _cleanSubtasks(List<SubtaskItem> subtasks) {
    return [
      for (final subtask in subtasks)
        if (subtask.title.trim().isNotEmpty)
          SubtaskItem(
            title: subtask.title.trim(),
            isCompleted: subtask.isCompleted,
          ),
    ];
  }

  /// Collects all task IDs, label IDs, and retained deletion record IDs so newly generated IDs never collide (`TDF_SPEC.md` Section 2.9).
  Set<String> _collectAllUsedEntityIds() {
    final ids = <String>{};
    for (final task in allTasks) {
      ids.add(task.id);
      ids.addAll(task.blockedByTaskIds);
      ids.addAll(task.labelIds);
    }
    for (final label in labels) {
      ids.add(label.id);
    }
    for (final record in deletedBlock.tasks) {
      ids.add(record.taskId);
    }
    for (final record in deletedBlock.labels) {
      ids.add(record.labelId);
    }
    return ids;
  }

  /// Compares two scheduled open tasks for initial default queue construction (`priority` first, then ascending `queuedAt`, then declaration index).
  static int _compareInitialQueueCandidates(
    _IndexedTask first,
    _IndexedTask second,
  ) {
    if (first.task.isPriority != second.task.isPriority) {
      return first.task.isPriority ? -1 : 1;
    }
    final firstQueued = first.task.queuedAt ?? first.task.createdAt;
    final secondQueued = second.task.queuedAt ?? second.task.createdAt;
    final timeCompare = firstQueued.compareTo(secondQueued);
    if (timeCompare != 0) {
      return timeCompare;
    }
    return first.index.compareTo(second.index);
  }

  /// Compares two [TdfLabel] instances alphabetically (case-insensitive, then case-sensitive, then by ID).
  static int _compareLabelsAlphabetically(TdfLabel first, TdfLabel second) {
    final lowerCompare = first.name.toLowerCase().compareTo(
      second.name.toLowerCase(),
    );
    if (lowerCompare != 0) {
      return lowerCompare;
    }
    final exactCompare = first.name.compareTo(second.name);
    if (exactCompare != 0) {
      return exactCompare;
    }
    return first.id.compareTo(second.id);
  }

  /// Derives a default [TdfQueueBlock] when `TaskBoard.evaluate` is invoked without an explicit `queueBlock`.
  static TdfQueueBlock _deriveDefaultQueueBlock(List<TaskItem> tasks) {
    final scheduledOpen = <_IndexedTask>[];
    DateTime? latestModified;
    for (var i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      if (!task.isCompleted &&
          task.completedAt == null &&
          task.queuedAt != null) {
        scheduledOpen.add(_IndexedTask(index: i, task: task));
        final effectiveMod = task.effectiveModifiedAt;
        if (latestModified == null || effectiveMod.isAfter(latestModified)) {
          latestModified = effectiveMod;
        }
      }
    }
    scheduledOpen.sort(_compareInitialQueueCandidates);
    return TdfQueueBlock(
      modifiedAt: latestModified ?? TdfQueueBlock.epochModifiedAt,
      taskIds: <String>[for (final entry in scheduledOpen) entry.task.id],
    );
  }

  /// Downgrades [task] from Tier 1 (`Focus`) to Tier 2 (`Ready`) per `TDF_SPEC.md` Section 6.3.
  TaskBoard _downgradeFromFocus(
    TaskItem task,
    DateTime now, {
    required DateTime localNow,
    required TdfTimeZoneContext? timeZone,
  }) {
    final totalEligibleCount = focus.length + ready.length + planned.length;
    if (totalEligibleCount < focusSoftLimit + readySoftLimit) {
      return _downgradeToQueueTail(
        task,
        now,
        localNow: localNow,
        timeZone: timeZone,
      );
    }

    final slot8Anchor = ready[readySoftLimit - 1];
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
    for (final id in queueBlock.taskIds) {
      if (id == task.id) {
        continue;
      }
      nextQueueIds.add(id);
      if (id == slot8Anchor.id) {
        nextQueueIds.add(task.id);
      }
    }
    if (!nextQueueIds.contains(task.id)) {
      nextQueueIds.add(task.id);
    }

    final queueChanged = !listEquals(nextQueueIds, queueBlock.taskIds);
    if (!priorityChanged && !queueChanged) {
      return this;
    }

    final nextQueueBlock = queueChanged
        ? TdfQueueBlock(
            modifiedAt: TaskItem.nextModifiedTimestamp(
              now,
              queueBlock.modifiedAt,
            ),
            taskIds: nextQueueIds,
          )
        : queueBlock;
    final updatedTasks = <TaskItem>[
      for (final item in allTasks) item.id == task.id ? updatedTask : item,
    ];

    return TaskBoard.evaluate(
      tasks: updatedTasks,
      evaluationTime: now,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      labels: labels,
      deletedBlock: deletedBlock,
      queueBlock: nextQueueBlock,
      pruneExpiredCompleted: true,
    );
  }

  /// Downgrades [task] from Tier 2 (`Ready`) to Tier 3 (`Planned`) per `TDF_SPEC.md` Section 6.3.
  TaskBoard _downgradeToPlanned(
    TaskItem task,
    DateTime now, {
    required DateTime localNow,
    required TdfTimeZoneContext? timeZone,
  }) {
    return _downgradeToQueueTail(
      task,
      now,
      localNow: localNow,
      timeZone: timeZone,
    );
  }

  /// Removes `priority` from [task] and moves its queue entry to the end of `queue` without changing `queuedAt` (`TDF_SPEC.md` Section 6.3).
  TaskBoard _downgradeToQueueTail(
    TaskItem task,
    DateTime now, {
    required DateTime localNow,
    required TdfTimeZoneContext? timeZone,
  }) {
    final priorityChanged = task.isPriority;
    final nextQueueIds = <String>[
      for (final id in queueBlock.taskIds)
        if (id != task.id) id,
      task.id,
    ];
    final queueChanged = !listEquals(nextQueueIds, queueBlock.taskIds);
    if (!priorityChanged && !queueChanged) {
      return this;
    }

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
              queueBlock.modifiedAt,
            ),
            taskIds: nextQueueIds,
          )
        : queueBlock;
    final updatedTasks = <TaskItem>[
      for (final item in allTasks) item.id == task.id ? updatedTask : item,
    ];

    return TaskBoard.evaluate(
      tasks: updatedTasks,
      evaluationTime: now,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      labels: labels,
      deletedBlock: deletedBlock,
      queueBlock: nextQueueBlock,
      pruneExpiredCompleted: true,
    );
  }

  /// Downgrades [task] from Tier 3 (`Planned`) to Tier 5 (`Someday`) per `TDF_SPEC.md` Section 6.3.
  TaskBoard _downgradeToSomeday(
    TaskItem task,
    DateTime now, {
    required DateTime localNow,
    required TdfTimeZoneContext? timeZone,
  }) {
    final downgradedTask = task.toActive(
      clearQueuedAt: true,
      isPriority: false,
      modifiedAt: TaskItem.nextModifiedTimestamp(now, task.effectiveModifiedAt),
    );
    final nextQueueBlock = _removeTaskFromQueue(queueBlock, task.id, now);
    final updatedTasks = <TaskItem>[
      for (final item in allTasks) item.id == task.id ? downgradedTask : item,
    ];

    return TaskBoard.evaluate(
      tasks: updatedTasks,
      evaluationTime: now,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      labels: labels,
      deletedBlock: deletedBlock,
      queueBlock: nextQueueBlock,
      pruneExpiredCompleted: true,
    );
  }

  /// Evaluates all rules belonging to [group] within [rules] using intra-group `OR` short-circuiting.
  static bool _evaluateGroupRules({
    required List<TaskCondition> rules,
    required ConditionGroup group,
    required DateTime evaluationTime,
    required double? currentLatitude,
    required double? currentLongitude,
  }) {
    var hasRuleInGroup = false;
    for (final rule in rules) {
      if (rule.group != group) {
        continue;
      }
      if (rule is GroupResetTaskCondition) {
        return true;
      }
      hasRuleInGroup = true;
      if (rule.isSatisfiedAt(
        evaluationTime,
        currentLatitude: currentLatitude,
        currentLongitude: currentLongitude,
      )) {
        return true;
      }
    }
    return !hasRuleInGroup;
  }

  /// Evaluates a single effective condition context (`day` AND `time` AND `location`) per Section 4.3.3.
  static bool _evaluateRuleContext({
    required List<TaskCondition> baseRules,
    required List<TaskCondition> taskRules,
    required DateTime evaluationTime,
    required double? currentLatitude,
    required double? currentLongitude,
  }) {
    for (final group in ConditionGroup.values) {
      final effectiveSource = _hasTaskRuleForGroup(taskRules, group)
          ? taskRules
          : baseRules;
      if (!_evaluateGroupRules(
        rules: effectiveSource,
        group: group,
        evaluationTime: evaluationTime,
        currentLatitude: currentLatitude,
        currentLongitude: currentLongitude,
      )) {
        return false;
      }
    }
    return true;
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

  /// Checks whether [task] has an active deferral (`suspended forever` or `suspendedAt > nowUtc`).
  static bool _hasActiveDeferral(TaskItem task, DateTime nowUtc) {
    if (task.isSuspendedForever) {
      return true;
    }
    if (task.suspendedAt case final suspendedUntil?
        when suspendedUntil.isAfter(nowUtc)) {
      return true;
    }
    return false;
  }

  /// Checks whether [conditions] contains a [GlobalResetTaskCondition] (`condition any`).
  static bool _hasGlobalReset(List<TaskCondition> conditions) {
    for (final condition in conditions) {
      if (condition is GlobalResetTaskCondition) {
        return true;
      }
    }
    return false;
  }

  /// Checks whether [conditions] contains a [GroupResetTaskCondition] for [group].
  static bool _hasGroupReset(
    List<TaskCondition> conditions,
    ConditionGroup group,
  ) {
    for (final condition in conditions) {
      if (condition is GroupResetTaskCondition &&
          condition.targetGroup == group) {
        return true;
      }
    }
    return false;
  }

  /// Checks whether [task] references at least one label ID present in [labelIdsWithConditions].
  static bool _hasInheritedLabelConditions(
    TaskItem task,
    Set<String> labelIdsWithConditions,
  ) {
    if (labelIdsWithConditions.isEmpty || task.labelIds.isEmpty) {
      return false;
    }
    for (final labelId in task.labelIds) {
      if (labelIdsWithConditions.contains(labelId)) {
        return true;
      }
    }
    return false;
  }

  /// Checks whether [taskRules] defines at least one override or reset for [group].
  static bool _hasTaskRuleForGroup(
    List<TaskCondition> taskRules,
    ConditionGroup group,
  ) {
    for (final rule in taskRules) {
      if (rule.group == group) {
        return true;
      }
    }
    return false;
  }

  /// Returns whether [targetTaskId] is reachable from [startTaskId] via `blockedByTaskIds` edges.
  static bool _isReachableInDependencyGraph({
    required String startTaskId,
    required String targetTaskId,
    required Map<String, TaskItem> taskMap,
  }) {
    final visited = <String>{};
    final frontier = <String>[startTaskId];
    var cursor = 0;
    while (cursor < frontier.length) {
      final currentId = frontier[cursor];
      cursor++;
      if (currentId == targetTaskId) {
        return true;
      }
      if (!visited.add(currentId)) {
        continue;
      }
      final currentTask = taskMap[currentId];
      if (currentTask != null) {
        frontier.addAll(currentTask.blockedByTaskIds);
      }
    }
    return false;
  }

  /// Evaluates whether [task] is blocked at [nowUtc] / [localNow] per `TDF_SPEC.md` Section 5.4:
  /// 1. Active deferral (`suspended forever` or `suspended > nowUtc` in UTC).
  /// 2. Unmet prerequisite (`target.completions < requiredCompletion` across the complete document).
  /// 3. Unmet activation condition (`day -> time -> location` against [localNow]).
  static bool _isTaskBlocked({
    required TaskItem task,
    required Map<String, TaskItem> taskMap,
    required Map<String, TdfLabel> labelMap,
    required DateTime nowUtc,
    required DateTime localNow,
    required String? activeLabelId,
    required double? currentLatitude,
    required double? currentLongitude,
  }) {
    if (_hasActiveDeferral(task, nowUtc)) {
      return true;
    }
    for (final dependency in task.dependencies) {
      final target = taskMap[dependency.taskId];
      if (target != null &&
          target.completions < dependency.requiredCompletion) {
        return true;
      }
    }
    if (!_areTaskConditionsSatisfied(
      task: task,
      labelMap: labelMap,
      evaluationTime: localNow,
      activeLabelId: activeLabelId,
      currentLatitude: currentLatitude,
      currentLongitude: currentLongitude,
    )) {
      return true;
    }
    return false;
  }

  /// Returns whether [timestamp] is strictly older than 30 days (`2,592,000` seconds) relative to [nowUtc].
  static bool _isTimestampExpired(DateTime timestamp, DateTime nowUtc) {
    return nowUtc.difference(timestamp.toUtc()).inSeconds >
        completedRetentionSeconds;
  }

  /// Returns whether [task] is within the 30-day (`2,592,000` seconds) retention window relative to [nowUtc].
  static bool _isWithinRetention(TaskItem task, DateTime nowUtc) {
    final completedDate = task.completedAt;
    if (completedDate == null) {
      return true;
    }
    return !_isTimestampExpired(completedDate, nowUtc);
  }

  /// Logs [action] with the resulting 6-tier task distribution under [LogTag.domain] and returns `this`.
  TaskBoard _logDomainMutation(String action) {
    AppLogger.info(
      LogTag.domain,
      '$action | tiers: Focus=${focus.length}, Ready=${ready.length}, Planned=${planned.length}, Blocked=${blocked.length}, Someday=${someday.length}, Completed=${completed.length}',
    );
    return this;
  }

  /// Merges [prunedRecords] into [current] without incrementing `generation`.
  static TdfDeletedBlock _mergePrunedTasksIntoDeletedBlock(
    TdfDeletedBlock current,
    List<TdfDeletedTaskRecord> prunedRecords,
  ) {
    if (prunedRecords.isEmpty) {
      return current;
    }
    var updated = current;
    for (final record in prunedRecords) {
      updated = _recordTaskDeletion(updated, record);
    }
    return updated;
  }

  /// Normalizes active tasks across `[focus, ready, planned]` so `queuedAt` is always populated.
  static void _normalizeActiveLists(
    List<TaskItem> focusList,
    List<TaskItem> readyList,
    List<TaskItem> plannedList,
  ) {
    var cursorTime = TaskItem.defaultCreatedAt;
    for (var i = 0; i < focusList.length; i++) {
      cursorTime = _normalizeSingleActiveTask(focusList, i, cursorTime);
    }
    for (var i = 0; i < readyList.length; i++) {
      cursorTime = _normalizeSingleActiveTask(readyList, i, cursorTime);
    }
    for (var i = 0; i < plannedList.length; i++) {
      cursorTime = _normalizeSingleActiveTask(plannedList, i, cursorTime);
    }
  }

  /// Normalizes a single active task at [index] in [list] and returns the updated fallback timestamp.
  static DateTime _normalizeSingleActiveTask(
    List<TaskItem> list,
    int index,
    DateTime defaultQueuedTime,
  ) {
    final current = list[index];
    final effectiveQueued = current.queuedAt ?? defaultQueuedTime;
    list[index] = current.copyWith(
      isCompleted: false,
      clearCompletedAt: true,
      queuedAt: effectiveQueued,
    );
    if (!current.isPriority && effectiveQueued.isAfter(defaultQueuedTime)) {
      return effectiveQueued;
    }
    return defaultQueuedTime;
  }

  /// Normalizes all 6 tier slices so their TDF directives match their tier placement.
  static _NormalizedTierSlices _normalizeTierSlices({
    required List<TaskItem> focus,
    required List<TaskItem> ready,
    required List<TaskItem> planned,
    required List<TaskItem> blocked,
    required List<TaskItem> someday,
    required List<TaskItem> completed,
    required List<TdfLabel> labels,
    required TdfQueueBlock? explicitQueueBlock,
  }) {
    final nextFocus = List<TaskItem>.from(focus);
    final nextReady = List<TaskItem>.from(ready);
    final nextPlanned = List<TaskItem>.from(planned);
    _normalizeActiveLists(nextFocus, nextReady, nextPlanned);
    final labelIdsWithConditions = <String>{
      for (final label in labels)
        if (label.conditions.isNotEmpty) label.id,
    };

    final nextBlocked = <TaskItem>[
      for (final task in blocked)
        task.copyWith(
          isCompleted: false,
          clearCompletedAt: true,
          queuedAt: task.queuedAt ?? task.createdAt,
          isSuspendedForever:
              task.isSuspendedForever ||
              (task.blockedByTaskIds.isEmpty &&
                  task.conditions.isEmpty &&
                  !_hasInheritedLabelConditions(task, labelIdsWithConditions) &&
                  task.suspendedAt == null),
        ),
    ];

    final nextSomeday = <TaskItem>[
      for (final task in someday)
        task.copyWith(
          isCompleted: false,
          clearCompletedAt: true,
          clearQueuedAt: true,
          isPriority: false,
        ),
    ];

    final nextCompleted = <TaskItem>[
      for (final task in completed) task.copyWith(isCompleted: true),
    ];

    final openCountsByLabel = <String, int>{};
    _accumulateListLabelCounts(nextFocus, openCountsByLabel);
    _accumulateListLabelCounts(nextReady, openCountsByLabel);
    _accumulateListLabelCounts(nextPlanned, openCountsByLabel);
    _accumulateListLabelCounts(nextBlocked, openCountsByLabel);
    _accumulateListLabelCounts(nextSomeday, openCountsByLabel);

    final resolvedQueueBlock =
        explicitQueueBlock ??
        _deriveSliceQueueBlock(
          focus: nextFocus,
          ready: nextReady,
          planned: nextPlanned,
          blocked: nextBlocked,
        );

    return _NormalizedTierSlices(
      focus: nextFocus,
      ready: nextReady,
      planned: nextPlanned,
      blocked: nextBlocked,
      someday: nextSomeday,
      completed: nextCompleted,
      openTaskCountsByLabel: openCountsByLabel,
      queueBlock: resolvedQueueBlock,
    );
  }

  /// Derives a [TdfQueueBlock] preserving the slice order of `[focus, ready, planned, blocked]`.
  static TdfQueueBlock _deriveSliceQueueBlock({
    required List<TaskItem> focus,
    required List<TaskItem> ready,
    required List<TaskItem> planned,
    required List<TaskItem> blocked,
  }) {
    final ids = <String>[];
    final seen = <String>{};
    DateTime? latestModified;
    for (final task in <TaskItem>[...focus, ...ready, ...planned, ...blocked]) {
      if (!task.isCompleted &&
          task.completedAt == null &&
          task.queuedAt != null &&
          seen.add(task.id)) {
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

  /// Orders eligible tasks by traversing [queueTaskIds] in saved order and grouping `priority` before regular per `TDF_SPEC.md` Section 5.5.
  static List<TaskItem> _orderEligibleByQueue({
    required Map<String, TaskItem> eligibleById,
    required List<String> queueTaskIds,
  }) {
    if (eligibleById.isEmpty) {
      return const <TaskItem>[];
    }
    final priorityGroup = <TaskItem>[];
    final regularGroup = <TaskItem>[];
    final visited = <String>{};

    for (final taskId in queueTaskIds) {
      final task = eligibleById[taskId];
      if (task != null && visited.add(taskId)) {
        if (task.isPriority) {
          priorityGroup.add(task);
        } else {
          regularGroup.add(task);
        }
      }
    }
    for (final entry in eligibleById.entries) {
      if (visited.add(entry.key)) {
        if (entry.value.isPriority) {
          priorityGroup.add(entry.value);
        } else {
          regularGroup.add(entry.value);
        }
      }
    }
    return <TaskItem>[...priorityGroup, ...regularGroup];
  }

  /// Rearms [dependencies] for the next occurrence of a recurring or restored task per `TDF_SPEC.md` Section 6.9.3.
  List<TdfTaskDependency> _rearmDependencies(
    List<TdfTaskDependency> dependencies,
  ) {
    if (dependencies.isEmpty) {
      return const <TdfTaskDependency>[];
    }
    final result = <TdfTaskDependency>[];
    for (final dep in dependencies) {
      final target = findTask(dep.taskId);
      if (target == null) {
        result.add(dep);
        continue;
      }
      if (target.isCompleted || target.completedAt != null) {
        result.add(
          TdfTaskDependency(
            taskId: dep.taskId,
            requiredCompletion: target.completions >= 1
                ? target.completions
                : 1,
          ),
        );
        continue;
      }
      if (target.completions >= TdfTaskDependency.maxCompletions) {
        throw const FormatException('LimitExceeded');
      }
      result.add(
        TdfTaskDependency(
          taskId: dep.taskId,
          requiredCompletion: target.completions + 1,
        ),
      );
    }
    return List<TdfTaskDependency>.unmodifiable(result);
  }

  /// Reconciles [currentQueue] when `copyWith` replaces tier slices without providing an explicit `queueBlock`.
  static TdfQueueBlock _reconcileQueueWithSlices({
    required TdfQueueBlock currentQueue,
    required List<TaskItem> focus,
    required List<TaskItem> ready,
    required List<TaskItem> planned,
    required List<TaskItem> blocked,
  }) {
    final scheduledOpenIds = <String>{};
    final orderedSliceIds = <String>[];
    for (final task in <TaskItem>[...focus, ...ready, ...planned, ...blocked]) {
      if (!task.isCompleted &&
          task.completedAt == null &&
          task.queuedAt != null &&
          scheduledOpenIds.add(task.id)) {
        orderedSliceIds.add(task.id);
      }
    }
    final reconciled = <String>[
      for (final id in currentQueue.taskIds)
        if (scheduledOpenIds.contains(id)) id,
    ];
    for (final id in orderedSliceIds) {
      if (!reconciled.contains(id)) {
        reconciled.add(id);
      }
    }
    if (listEquals(reconciled, currentQueue.taskIds)) {
      return currentQueue;
    }
    return TdfQueueBlock(
      modifiedAt: currentQueue.modifiedAt,
      taskIds: reconciled,
    );
  }

  /// Records a label deletion in [current] while enforcing `TdfDeletedBlock.maxDeletedRecords`.
  static TdfDeletedBlock _recordLabelDeletion(
    TdfDeletedBlock current,
    TdfDeletedLabelRecord record,
  ) {
    final nextLabels = <TdfDeletedLabelRecord>[...current.labels, record];
    final candidate = current.copyWith(labels: nextLabels);
    if (candidate.totalRecords > TdfDeletedBlock.maxDeletedRecords) {
      throw const FormatException('LimitExceeded');
    }
    return candidate;
  }

  /// Records a task deletion in [current] while enforcing `TdfDeletedBlock.maxDeletedRecords`.
  static TdfDeletedBlock _recordTaskDeletion(
    TdfDeletedBlock current,
    TdfDeletedTaskRecord record,
  ) {
    final nextTasks = <TdfDeletedTaskRecord>[...current.tasks, record];
    final candidate = current.copyWith(tasks: nextTasks);
    if (candidate.totalRecords > TdfDeletedBlock.maxDeletedRecords) {
      throw const FormatException('LimitExceeded');
    }
    return candidate;
  }

  /// Returns [task] without [labelId] in its `labelIds` list.
  static TaskItem _removeIdFromTaskLabels(
    TaskItem task,
    String labelId,
    DateTime? now,
  ) {
    if (!task.labelIds.contains(labelId)) {
      return task;
    }
    return task.copyWith(
      labelIds: [
        for (final id in task.labelIds)
          if (id != labelId) id,
      ],
      modifiedAt: now != null
          ? TaskItem.nextModifiedTimestamp(now, task.effectiveModifiedAt)
          : task.modifiedAt,
    );
  }

  /// Removes [taskId] from [queue] if present, advancing `queue.modified` when changed.
  static TdfQueueBlock _removeTaskFromQueue(
    TdfQueueBlock queue,
    String taskId,
    DateTime now,
  ) {
    if (!queue.taskIds.contains(taskId)) {
      return queue;
    }
    return TdfQueueBlock(
      modifiedAt: TaskItem.nextModifiedTimestamp(now, queue.modifiedAt),
      taskIds: <String>[
        for (final id in queue.taskIds)
          if (id != taskId) id,
      ],
    );
  }

  /// Replaces the task with `updatedTask.id` inside [tier].
  TaskBoard _replaceTaskInTier(TaskTier tier, TaskItem updatedTask) {
    List<TaskItem> replaceIn(List<TaskItem> list) {
      return [
        for (final item in list) item.id == updatedTask.id ? updatedTask : item,
      ];
    }

    return switch (tier) {
      TaskTier.focus => copyWith(focus: replaceIn(focus)),
      TaskTier.ready => copyWith(ready: replaceIn(ready)),
      TaskTier.planned => copyWith(planned: replaceIn(planned)),
      TaskTier.blocked => copyWith(blocked: replaceIn(blocked)),
      TaskTier.someday => copyWith(someday: replaceIn(someday)),
      TaskTier.completed => copyWith(completed: replaceIn(completed)),
    };
  }

  /// Reschedules a completed recurring [task] for its next cycle per `TDF_SPEC.md` Sections 6.4, 6.9.3, and 6.10.3.
  TaskItem _rescheduleRecurringTask(
    TaskItem task,
    TaskRepeatRule repeatRule,
    DateTime now,
    TdfTimeZoneContext timeZone, {
    DateTime? preserveModifiedAt,
  }) {
    if (task.completions >= TdfTaskDependency.maxCompletions) {
      throw const FormatException('LimitExceeded');
    }
    final nextDueUtc = repeatRule.nextDueUtc(
      completedAtUtc: now,
      timeZone: timeZone,
    );
    final resetSubtasks = _setAllSubtasksCompleted(
      task.subtasks,
      isCompleted: false,
    );
    final rearmedDependencies = _rearmDependencies(task.dependencies);
    final nextModified =
        preserveModifiedAt ??
        TaskItem.nextModifiedTimestamp(now, task.effectiveModifiedAt);
    AppLogger.info(
      LogTag.domain,
      'Rescheduled recurring task id=${task.id} repeat -> nextDueUtc=${nextDueUtc.toIso8601String()}',
    );
    return task.copyWith(
      isCompleted: false,
      clearCompletedAt: true,
      completions: task.completions + 1,
      isPriority: true,
      queuedAt: nextDueUtc,
      suspendedAt: nextDueUtc,
      isSuspendedForever: false,
      repeatRule: repeatRule,
      dependencies: rearmedDependencies,
      subtasks: resetSubtasks,
      modifiedAt: nextModified,
    );
  }

  /// Resolves the effective [TdfTimeZoneContext] from [timeZone] or [localEvaluationTime].
  static TdfTimeZoneContext _resolveEffectiveTimeZone({
    required DateTime now,
    required DateTime? localEvaluationTime,
    required TdfTimeZoneContext? timeZone,
  }) {
    if (timeZone != null) {
      return timeZone;
    }
    if (localEvaluationTime != null) {
      final localWall = _resolveLocalEvaluationTime(now, localEvaluationTime);
      return TdfTimeZoneContext.fixedOffset(localWall.difference(now));
    }
    return TdfTimeZoneContext.utc;
  }

  /// Resolves the effective local wall-clock evaluation timestamp for `condition day` and `condition time`.
  static DateTime _resolveLocalEvaluationTime(
    DateTime? evaluationTime,
    DateTime? localEvaluationTime,
  ) {
    if (localEvaluationTime != null) {
      return DateTime.utc(
        localEvaluationTime.year,
        localEvaluationTime.month,
        localEvaluationTime.day,
        localEvaluationTime.hour,
        localEvaluationTime.minute,
        localEvaluationTime.second,
      );
    }
    if (evaluationTime != null) {
      return DateTime.utc(
        evaluationTime.year,
        evaluationTime.month,
        evaluationTime.day,
        evaluationTime.hour,
        evaluationTime.minute,
        evaluationTime.second,
      );
    }
    final systemLocal = DateTime.now();
    return DateTime.utc(
      systemLocal.year,
      systemLocal.month,
      systemLocal.day,
      systemLocal.hour,
      systemLocal.minute,
      systemLocal.second,
    );
  }

  /// Orders [conditions] for a `label` block by group (`day`, `time`, `location`) while stripping task-only resets (`TDF_SPEC.md` Section 4.3).
  static List<TaskCondition> _sanitizeLabelConditions(
    List<TaskCondition> conditions,
  ) {
    if (conditions.isEmpty) {
      return const [];
    }
    final dayRules = <DayTaskCondition>[];
    final timeRules = <TimeWindowTaskCondition>[];
    final locationRules = <LocationTaskCondition>[];

    for (final condition in conditions) {
      switch (condition) {
        case GlobalResetTaskCondition():
        case GroupResetTaskCondition():
          break;
        case DayTaskCondition():
          dayRules.add(condition);
        case TimeWindowTaskCondition():
          timeRules.add(condition);
        case LocationTaskCondition():
          locationRules.add(condition);
      }
    }

    return List<TaskCondition>.unmodifiable([
      ...dayRules,
      ...timeRules,
      ...locationRules,
    ]);
  }

  /// Orders [conditions] for a `task` block by group (`day`, `time`, `location`) while enforcing `TDF_SPEC.md` Section 4.3 reset rules.
  static List<TaskCondition> _sanitizeTaskConditions(
    List<TaskCondition> conditions,
  ) {
    if (conditions.isEmpty) {
      return const [];
    }
    if (_hasGlobalReset(conditions)) {
      return const [GlobalResetTaskCondition()];
    }
    final hasDayReset = _hasGroupReset(conditions, ConditionGroup.day);
    final hasTimeReset = _hasGroupReset(conditions, ConditionGroup.time);
    final hasLocationReset = _hasGroupReset(
      conditions,
      ConditionGroup.location,
    );
    final dayRules = <DayTaskCondition>[];
    final timeRules = <TimeWindowTaskCondition>[];
    final locationRules = <LocationTaskCondition>[];

    for (final condition in conditions) {
      switch (condition) {
        case GlobalResetTaskCondition():
        case GroupResetTaskCondition():
          break;
        case DayTaskCondition():
          if (!hasDayReset) {
            dayRules.add(condition);
          }
        case TimeWindowTaskCondition():
          if (!hasTimeReset) {
            timeRules.add(condition);
          }
        case LocationTaskCondition():
          if (!hasLocationReset) {
            locationRules.add(condition);
          }
      }
    }

    return List<TaskCondition>.unmodifiable([
      if (hasDayReset)
        const GroupResetTaskCondition(targetGroup: ConditionGroup.day)
      else
        ...dayRules,
      if (hasTimeReset)
        const GroupResetTaskCondition(targetGroup: ConditionGroup.time)
      else
        ...timeRules,
      if (hasLocationReset)
        const GroupResetTaskCondition(targetGroup: ConditionGroup.location)
      else
        ...locationRules,
    ]);
  }

  /// Returns a list of [subtasks] with every step's `isCompleted` state set to [isCompleted].
  static List<SubtaskItem> _setAllSubtasksCompleted(
    List<SubtaskItem> subtasks, {
    required bool isCompleted,
  }) {
    if (subtasks.isEmpty) {
      return subtasks;
    }
    return <SubtaskItem>[
      for (final step in subtasks)
        step.isCompleted == isCompleted
            ? step
            : step.copyWith(isCompleted: isCompleted),
    ];
  }

  /// Slices ordered [eligibleTasks] into `Focus` (`0..2`), `Ready` (`3..7`), and `Planned` (`>= 8`).
  static void _sliceEligibleTasks(
    List<TaskItem> eligibleTasks, {
    required List<TaskItem> focusList,
    required List<TaskItem> readyList,
    required List<TaskItem> plannedList,
  }) {
    for (var i = 0; i < eligibleTasks.length; i++) {
      final task = eligibleTasks[i];
      if (i < focusSoftLimit) {
        focusList.add(task);
      } else if (i < focusSoftLimit + readySoftLimit) {
        readyList.add(task);
      } else {
        plannedList.add(task);
      }
    }
  }

  /// Returns an unmodifiable copy of [labels] sorted alphabetically by display name.
  static List<TdfLabel> _sortLabelsAlphabetically(List<TdfLabel> labels) {
    if (labels.isEmpty) {
      return const [];
    }
    final sorted = List<TdfLabel>.from(labels)
      ..sort(_compareLabelsAlphabetically);
    return List<TdfLabel>.unmodifiable(sorted);
  }

  /// Removes [labelId] from every task in [tasks].
  static List<TaskItem> _stripLabelFromTasks(
    List<TaskItem> tasks,
    String labelId,
    DateTime? now,
  ) {
    return [
      for (final task in tasks) _removeIdFromTaskLabels(task, labelId, now),
    ];
  }

  /// Updates [currentQueue] after [existingTask] is edited into [updatedTask].
  static TdfQueueBlock _updateQueueForEditedTask({
    required TdfQueueBlock currentQueue,
    required TaskItem existingTask,
    required TaskItem updatedTask,
    required DateTime now,
  }) {
    final isNowScheduledOpen =
        !updatedTask.isCompleted &&
        updatedTask.completedAt == null &&
        updatedTask.queuedAt != null;
    final wasCompleted =
        existingTask.isCompleted || existingTask.completedAt != null;
    if (!isNowScheduledOpen) {
      return _removeTaskFromQueue(currentQueue, updatedTask.id, now);
    }
    if (wasCompleted) {
      final withoutTask = _removeTaskFromQueue(
        currentQueue,
        updatedTask.id,
        now,
      );
      return _appendTaskToQueue(withoutTask, updatedTask.id, now);
    }
    return _appendTaskToQueue(currentQueue, updatedTask.id, now);
  }
}

/// Pairs a [TaskItem] with its zero-based document declaration index for stable tie-breaking.
class _IndexedTask {
  /// Creates an [_IndexedTask].
  const _IndexedTask({required this.index, required this.task});

  /// Zero-based declaration index in the source document.
  final int index;

  /// Evaluated task item.
  final TaskItem task;
}

/// Holds the normalized task lists for all 6 tiers during [TaskBoard] construction.
class _NormalizedTierSlices {
  /// Creates [_NormalizedTierSlices].
  const _NormalizedTierSlices({
    required this.focus,
    required this.ready,
    required this.planned,
    required this.blocked,
    required this.someday,
    required this.completed,
    required this.openTaskCountsByLabel,
    required this.queueBlock,
  });

  /// Normalized Tier 4 (`Blocked`) tasks.
  final List<TaskItem> blocked;

  /// Normalized Tier 6 (`Completed`) tasks.
  final List<TaskItem> completed;

  /// Normalized Tier 1 (`Focus`) tasks.
  final List<TaskItem> focus;

  /// Precomputed open task counts across tiers `1` to `5` keyed by label ID.
  final Map<String, int> openTaskCountsByLabel;

  /// Normalized Tier 3 (`Planned`) tasks.
  final List<TaskItem> planned;

  /// Normalized shared `queue` block.
  final TdfQueueBlock queueBlock;

  /// Normalized Tier 2 (`Ready`) tasks.
  final List<TaskItem> ready;

  /// Normalized Tier 5 (`Someday`) tasks.
  final List<TaskItem> someday;
}
