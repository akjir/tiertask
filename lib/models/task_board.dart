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
import 'tdf_metadata.dart';

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
  }) : this._normalized(
         _normalizeTierSlices(
           focus: focus,
           ready: ready,
           planned: planned,
           blocked: blocked,
           someday: someday,
           completed: completed,
         ),
         labels: labels,
       );

  TaskBoard._normalized(
    _NormalizedTierSlices slices, {
    required List<TdfLabel> labels,
  }) : focus = List<TaskItem>.unmodifiable(slices.focus),
       ready = List<TaskItem>.unmodifiable(slices.ready),
       planned = List<TaskItem>.unmodifiable(slices.planned),
       blocked = List<TaskItem>.unmodifiable(slices.blocked),
       someday = List<TaskItem>.unmodifiable(slices.someday),
       completed = List<TaskItem>.unmodifiable(slices.completed),
       labels = List<TdfLabel>.unmodifiable(labels);

  /// Creates an empty [TaskBoard] across all 6 tiers.
  factory TaskBoard.empty() => TaskBoard();

  /// Derives the 6 operational tiers from [tasks] in a single $O(N)$ pass per `TDF_SPEC.md` Section 5.
  factory TaskBoard.evaluate({
    required Iterable<TaskItem> tasks,
    DateTime? evaluationTime,
    List<TdfLabel> labels = const [],
    String? activeLabelId,
    double? currentLatitude,
    double? currentLongitude,
    bool pruneExpiredCompleted = false,
  }) {
    final now = evaluationTime ?? DateTime.now().toUtc();
    final normalizedNow = DateTime.utc(now.year, now.month, now.day);
    final taskList = List<TaskItem>.from(tasks);
    final unfinishedIds = _collectUnfinishedIds(taskList);
    final labelMap = <String, TdfLabel>{
      for (final label in labels) label.id: label,
    };

    final completedList = <TaskItem>[];
    final somedayList = <TaskItem>[];
    final blockedList = <TaskItem>[];
    final activeCandidates = <_IndexedTask>[];

    for (var i = 0; i < taskList.length; i++) {
      _classifyTaskIntoPipeline(
        task: taskList[i],
        index: i,
        now: now,
        normalizedNow: normalizedNow,
        unfinishedIds: unfinishedIds,
        labelMap: labelMap,
        activeLabelId: activeLabelId,
        currentLatitude: currentLatitude,
        currentLongitude: currentLongitude,
        pruneExpiredCompleted: pruneExpiredCompleted,
        completedList: completedList,
        somedayList: somedayList,
        blockedList: blockedList,
        activeCandidates: activeCandidates,
      );
    }

    activeCandidates.sort(_compareActiveCandidates);
    final focusList = <TaskItem>[];
    final readyList = <TaskItem>[];
    final plannedList = <TaskItem>[];
    _sliceActiveCandidates(
      activeCandidates,
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
    );
  }

  /// Retention period in days for completed tasks in Tier 6 (`Completed`).
  static const int completedRetentionDays = 30;

  /// Soft WIP limit for Tier 1 (`Focus`).
  static const int focusSoftLimit = 3;

  /// Soft WIP limit for Tier 2 (`Ready`).
  static const int readySoftLimit = 5;

  /// Tier 4 (`Blocked`) task items.
  final List<TaskItem> blocked;

  /// Tier 6 (`Completed`) task items.
  final List<TaskItem> completed;

  /// Tier 1 (`Focus`) task items.
  final List<TaskItem> focus;

  /// Defined TDF `label` blocks in declaration order.
  final List<TdfLabel> labels;

  /// Tier 3 (`Planned`) task items.
  final List<TaskItem> planned;

  /// Tier 2 (`Ready`) task items.
  final List<TaskItem> ready;

  /// Tier 5 (`Someday`) task items.
  final List<TaskItem> someday;

  /// Returns all tasks across all 6 tiers in canonical document order.
  List<TaskItem> get allTasks => List<TaskItem>.unmodifiable([
    ...focus,
    ...ready,
    ...planned,
    ...blocked,
    ...someday,
    ...completed,
  ]);

  /// Adds a new TDF `label` block with a unique identifier and optional `#RRGGBB` [color].
  TaskBoard addLabel(
    String name, {
    String? color,
    String? id,
    String? note,
    List<TaskCondition> conditions = const [],
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return this;
    }
    final existingIds = <String>{for (final label in labels) label.id};
    final baseId = (id != null && id.trim().isNotEmpty)
        ? id.trim()
        : _slugifyContextName(trimmed, 'l');
    final labelId = _ensureUniqueContextId(baseId, existingIds);
    final normalizedColor = TdfColor.normalizeHex(color);
    final newLabel = TdfLabel(
      id: labelId,
      name: trimmed,
      color: normalizedColor,
      note: note,
      conditions: List<TaskCondition>.unmodifiable(conditions),
    );
    return copyWith(labels: [...labels, newLabel]);
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
    String? id,
    String? note,
    List<String> labelIds = const [],
    DateTime? suspendedAt,
    List<String> blockedByTaskIds = const [],
    List<TaskCondition> conditions = const [],
  }) {
    final trimmed = title.trim();
    if (trimmed.isEmpty || hasDuplicateTaskTitle(trimmed)) {
      return this;
    }

    final now = currentDate ?? DateTime.now().toUtc();
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
    final isDone = targetTier == TaskTier.completed || autoCompleted;
    final isBlocked = targetTier == TaskTier.blocked && !isDone;
    final effectiveSuspendedAt = isDone
        ? null
        : (suspendedAt ?? (isBlocked ? TaskItem.defaultSuspendedAt : null));
    final isActivelySuspended =
        effectiveSuspendedAt != null && effectiveSuspendedAt.isAfter(now);
    final isSomeday =
        targetTier == TaskTier.someday && !isDone && !isActivelySuspended;
    final taskId = id ?? _generateUniqueTaskId();
    final cleanBlockedBy = _sanitizeBlockedByForTask(taskId, blockedByTaskIds);
    final cleanConditions = _sanitizeTaskConditions(conditions);

    final newTask = TaskItem(
      id: taskId,
      title: trimmed,
      note: effectiveNote,
      isCompleted: isDone,
      isPriority: effectivePriority && !isSomeday && !isBlocked,
      createdAt: now,
      queuedAt: isSomeday ? null : now,
      completedAt: isDone ? now : null,
      suspendedAt: effectiveSuspendedAt,
      blockedByTaskIds: cleanBlockedBy,
      labelIds: labelIds,
      conditions: cleanConditions,
      subtasksAutoFinish: subtasksAutoFinish,
      subtasks: cleanSubtasks,
    );

    if (isDone) {
      return copyWith(completed: [newTask, ...completed])
          .pruneCompletedTasks(currentDate: now)
          .applyAutoPull(currentDate: now);
    }

    return TaskBoard.evaluate(
      tasks: [...allTasks, newTask],
      evaluationTime: now,
      labels: labels,
      pruneExpiredCompleted: true,
    );
  }

  /// Evaluates the active pull cycle and unblocks any tasks whose prerequisites or deferrals cleared.
  TaskBoard applyAutoPull({DateTime? currentDate}) {
    final now = currentDate ?? DateTime.now().toUtc();
    final unfinishedIds = _collectUnfinishedIds(allTasks);
    final labelMap = <String, TdfLabel>{
      for (final label in labels) label.id: label,
    };
    final nextFocus = List<TaskItem>.from(focus);
    final nextReady = List<TaskItem>.from(ready);
    final nextPlanned = List<TaskItem>.from(planned);
    final nextBlocked = <TaskItem>[];

    for (final task in blocked) {
      if (_isTaskBlocked(
        task: task,
        unfinishedIds: unfinishedIds,
        labelMap: labelMap,
        evaluationTime: now,
        activeLabelId: null,
        currentLatitude: null,
        currentLongitude: null,
      )) {
        nextBlocked.add(task);
      } else {
        nextPlanned.add(task.copyWith(queuedAt: task.queuedAt ?? now));
      }
    }

    _cascadeQueues(
      nextFocus: nextFocus,
      nextReady: nextReady,
      nextPlanned: nextPlanned,
    );

    return copyWith(
      focus: nextFocus,
      ready: nextReady,
      planned: nextPlanned,
      blocked: nextBlocked,
    );
  }

  /// Moves an active task immediately to Tier 4 (`Blocked`) and refills vacated active slots.
  TaskBoard blockTask(
    String taskId, {
    DateTime? currentDate,
    DateTime? suspendedUntil,
  }) {
    final now = currentDate ?? DateTime.now().toUtc();
    final sourceTier = findTierOfTask(taskId);
    if (sourceTier == null || sourceTier == TaskTier.blocked) {
      return this;
    }
    final task = findTask(taskId);
    if (task == null) {
      return this;
    }

    final blockedTask = task.copyWith(
      isCompleted: false,
      clearCompletedAt: true,
      isPriority: false,
      queuedAt: task.queuedAt ?? now,
      suspendedAt: suspendedUntil ?? TaskItem.defaultSuspendedAt,
    );

    return _removeTaskFromTier(taskId, sourceTier)
        .copyWith(blocked: [...blocked, blockedTask])
        .pruneCompletedTasks(currentDate: now)
        .applyAutoPull(currentDate: now);
  }

  /// Marks an active task as done per `TDF_SPEC.md` Section 6.5:
  /// 1. Sets `finished` to [currentDate] and places it at the top of Tier 6 (`Completed`).
  /// 2. Prunes items in Tier 6 older than 30 days.
  /// 3. Unblocks any tasks waiting on [taskId] and refills Tier 1 and Tier 2.
  TaskBoard completeTask(String taskId, {DateTime? currentDate}) {
    final now = currentDate ?? DateTime.now().toUtc();
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

    return updated
        .pruneCompletedTasks(currentDate: now)
        .applyAutoPull(currentDate: now);
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
  }) {
    return TaskBoard(
      focus: focus ?? this.focus,
      ready: ready ?? this.ready,
      planned: planned ?? this.planned,
      blocked: blocked ?? this.blocked,
      someday: someday ?? this.someday,
      completed: completed ?? this.completed,
      labels: labels ?? this.labels,
    );
  }

  /// Deletes the label with [labelId] and removes its reference from all tasks.
  TaskBoard deleteLabel(String labelId) {
    final nextLabels = <TdfLabel>[
      for (final label in labels)
        if (label.id != labelId) label,
    ];
    if (nextLabels.length == labels.length) {
      return this;
    }
    return copyWith(
      focus: _stripLabelFromTasks(focus, labelId),
      ready: _stripLabelFromTasks(ready, labelId),
      planned: _stripLabelFromTasks(planned, labelId),
      blocked: _stripLabelFromTasks(blocked, labelId),
      someday: _stripLabelFromTasks(someday, labelId),
      completed: _stripLabelFromTasks(completed, labelId),
      labels: nextLabels,
    );
  }

  /// Downgrades a task in `Focus` (to `Ready`), `Ready` (to `Planned`), or `Planned` (to `Someday`) per `TDF_SPEC.md` Section 6.3.
  TaskBoard downgradeTask(String taskId, {DateTime? currentDate}) {
    final now = currentDate ?? DateTime.now().toUtc();
    final sourceTier = findTierOfTask(taskId);
    if (sourceTier == null) {
      return this;
    }
    final task = findTask(taskId);
    if (task == null) {
      return this;
    }

    if (sourceTier == TaskTier.focus) {
      return _downgradeFromFocus(task, now);
    }
    if (sourceTier == TaskTier.ready) {
      return _downgradeToPlanned(task, now);
    }
    if (sourceTier == TaskTier.planned) {
      return _downgradeToSomeday(task, now);
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
  }) {
    return TaskBoard.evaluate(
      tasks: allTasks,
      evaluationTime: evaluationTime,
      labels: labels,
      activeLabelId: activeLabelId,
      currentLatitude: currentLatitude,
      currentLongitude: currentLongitude,
    );
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

  /// Counts how many open (non-completed) tasks across tiers `1` to `5` reference [labelId].
  int openTaskCountForLabel(String labelId) {
    var count = 0;
    for (final task in allTasks) {
      if (!task.isCompleted &&
          task.completedAt == null &&
          task.labelIds.contains(labelId)) {
        count++;
      }
    }
    return count;
  }

  /// Prunes tasks in Tier 6 (`Completed`) older than 30 days (UTC) per `TDF_SPEC.md` Section 5.1.
  TaskBoard pruneCompletedTasks({DateTime? currentDate}) {
    final now = currentDate ?? DateTime.now().toUtc();
    final normalizedNow = DateTime.utc(now.year, now.month, now.day);

    final retained = <TaskItem>[
      for (final task in completed)
        if (_isWithinRetention(task, normalizedNow)) task,
    ];

    return copyWith(completed: retained);
  }

  /// Updates the display [name] of the label with [labelId], ignoring empty names.
  TaskBoard renameLabel(String labelId, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return this;
    }
    final nextLabels = <TdfLabel>[
      for (final label in labels)
        label.id == labelId ? label.copyWith(name: trimmed) : label,
    ];
    return copyWith(labels: nextLabels);
  }

  /// Restores a completed task back into `Someday`, `Planned`, or `Focus` per `TDF_SPEC.md` Section 6.5.
  TaskBoard restoreTask(
    String taskId, {
    TaskTier targetTier = TaskTier.planned,
    DateTime? currentDate,
  }) {
    if (targetTier == TaskTier.completed) {
      return this;
    }
    final now = currentDate ?? DateTime.now().toUtc();
    final existing = findTask(taskId);
    if (existing == null ||
        (!existing.isCompleted && existing.completedAt == null)) {
      return this;
    }

    final isSomeday = targetTier == TaskTier.someday;
    final isFocus = targetTier == TaskTier.focus;
    final restored = existing.copyWith(
      isCompleted: false,
      clearCompletedAt: true,
      queuedAt: isSomeday ? null : now,
      clearQueuedAt: isSomeday,
      isPriority: isFocus,
    );
    final updatedTasks = <TaskItem>[
      for (final task in allTasks) task.id == taskId ? restored : task,
    ];

    return TaskBoard.evaluate(
      tasks: updatedTasks,
      evaluationTime: now,
      labels: labels,
      pruneExpiredCompleted: true,
    );
  }

  /// Schedules a task from `Someday` into the active pull cycle per `TDF_SPEC.md` Section 6.2.
  TaskBoard scheduleTask(
    String taskId, {
    DateTime? currentDate,
    bool isPriority = false,
  }) {
    final now = currentDate ?? DateTime.now().toUtc();
    final existing = findTask(taskId);
    if (existing == null) {
      return this;
    }

    final scheduled = existing.copyWith(
      isCompleted: false,
      clearCompletedAt: true,
      queuedAt: now,
      isPriority: isPriority || existing.isPriority,
    );
    final updatedTasks = <TaskItem>[
      for (final task in allTasks) task.id == taskId ? scheduled : task,
    ];

    return TaskBoard.evaluate(
      tasks: updatedTasks,
      evaluationTime: now,
      labels: labels,
      pruneExpiredCompleted: true,
    );
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
  }) {
    final now = currentDate ?? DateTime.now().toUtc();
    final tier = findTierOfTask(taskId);
    final task = findTask(taskId);
    if (tier == null || task == null) {
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
    final updatedTask = task.copyWith(subtasks: updatedSubtasks);
    final replacedBoard = _replaceTaskInTier(tier, updatedTask);

    final allStepsDone =
        updatedSubtasks.isNotEmpty &&
        updatedSubtasks.every((step) => step.isCompleted);
    if (updatedTask.subtasksAutoFinish &&
        allStepsDone &&
        tier != TaskTier.completed) {
      return replacedBoard.completeTask(taskId, currentDate: now);
    }
    return replacedBoard;
  }

  /// Updates an existing task with [taskId], re-evaluates the 6-tier pipeline,
  /// and ignores empty or duplicate task titles.
  TaskBoard updateTask(
    String taskId, {
    required String title,
    String? note,
    TaskTier? targetTier,
    bool? isPriority,
    bool? subtasksAutoFinish,
    List<SubtaskItem>? subtasks,
    List<String>? labelIds,
    DateTime? suspendedAt,
    bool clearSuspendedAt = false,
    List<String>? blockedByTaskIds,
    List<TaskCondition>? conditions,
    DateTime? currentDate,
  }) {
    final trimmed = title.trim();
    if (trimmed.isEmpty ||
        hasDuplicateTaskTitle(trimmed, excludingTaskId: taskId)) {
      return this;
    }
    final existing = findTask(taskId);
    if (existing == null) {
      return this;
    }

    final now = currentDate ?? DateTime.now().toUtc();
    final sanitizedBlockedBy = blockedByTaskIds != null
        ? _sanitizeBlockedByForTask(taskId, blockedByTaskIds)
        : null;
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
      clearSuspendedAt: clearSuspendedAt,
      blockedByTaskIds: sanitizedBlockedBy,
      conditions: sanitizedConditions,
      now: now,
    );
    final updatedTasks = <TaskItem>[
      for (final task in allTasks) task.id == taskId ? updatedTask : task,
    ];

    return TaskBoard.evaluate(
      tasks: updatedTasks,
      evaluationTime: now,
      labels: labels,
      pruneExpiredCompleted: true,
    );
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

  /// Builds an updated [TaskItem] from [existing] with normalized scheduling and subtask fields.
  static TaskItem _buildUpdatedTask({
    required TaskItem existing,
    required String title,
    required String? note,
    required TaskTier? targetTier,
    required bool? isPriority,
    required bool? subtasksAutoFinish,
    required List<SubtaskItem>? subtasks,
    required List<String>? labelIds,
    required DateTime? suspendedAt,
    required bool clearSuspendedAt,
    required List<String>? blockedByTaskIds,
    required List<TaskCondition>? conditions,
    required DateTime now,
  }) {
    final wasCompleted = existing.isCompleted || existing.completedAt != null;
    final isRestoringCompleted =
        wasCompleted && targetTier != null && targetTier != TaskTier.completed;
    final effectiveAutoFinish =
        subtasksAutoFinish ?? existing.subtasksAutoFinish;
    final cleanSubtasks = subtasks != null
        ? _cleanSubtasks(subtasks)
        : existing.subtasks;
    final autoCompleted =
        !isRestoringCompleted &&
        effectiveAutoFinish &&
        cleanSubtasks.isNotEmpty &&
        cleanSubtasks.every((step) => step.isCompleted);
    final isDone =
        targetTier == TaskTier.completed ||
        autoCompleted ||
        (targetTier == null && wasCompleted);
    final isBlocked = !isDone && targetTier == TaskTier.blocked;
    final effectiveSuspendedAt = isDone || clearSuspendedAt
        ? null
        : (suspendedAt ??
              (isBlocked
                  ? (existing.suspendedAt ?? TaskItem.defaultSuspendedAt)
                  : existing.suspendedAt));
    final isActivelySuspended =
        effectiveSuspendedAt != null && effectiveSuspendedAt.isAfter(now);
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
        !isBlocked &&
        (preservedPriority || targetTier == TaskTier.focus);
    final effectiveQueuedAt = isSomeday
        ? null
        : (isRestoringCompleted ? now : (existing.queuedAt ?? now));
    final trimmedNote = note?.trim();

    return existing.copyWith(
      title: title,
      note: (trimmedNote != null && trimmedNote.isNotEmpty)
          ? trimmedNote
          : null,
      clearNote: trimmedNote != null && trimmedNote.isEmpty,
      isCompleted: isDone,
      completedAt: isDone ? (existing.completedAt ?? now) : null,
      clearCompletedAt: !isDone,
      isPriority: effectivePriority,
      queuedAt: effectiveQueuedAt,
      clearQueuedAt: isSomeday,
      suspendedAt: effectiveSuspendedAt,
      clearSuspendedAt: effectiveSuspendedAt == null,
      blockedByTaskIds: blockedByTaskIds,
      labelIds: labelIds,
      conditions: conditions,
      subtasksAutoFinish: effectiveAutoFinish,
      subtasks: cleanSubtasks,
    );
  }

  /// Executes the two-stage pull cascade across mutable queue lists in linear order.
  static void _cascadeQueues({
    required List<TaskItem> nextFocus,
    required List<TaskItem> nextReady,
    required List<TaskItem> nextPlanned,
  }) {
    var readyIndex = 0;
    while (nextFocus.length < focusSoftLimit && readyIndex < nextReady.length) {
      nextFocus.add(nextReady[readyIndex].toActive());
      readyIndex++;
    }
    if (readyIndex > 0) {
      nextReady.removeRange(0, readyIndex);
    }

    var plannedIndex = 0;
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

  /// Classifies a single [task] into the Section 5 evaluation buckets.
  static void _classifyTaskIntoPipeline({
    required TaskItem task,
    required int index,
    required DateTime now,
    required DateTime normalizedNow,
    required Set<String> unfinishedIds,
    required Map<String, TdfLabel> labelMap,
    required String? activeLabelId,
    required double? currentLatitude,
    required double? currentLongitude,
    required bool pruneExpiredCompleted,
    required List<TaskItem> completedList,
    required List<TaskItem> somedayList,
    required List<TaskItem> blockedList,
    required List<_IndexedTask> activeCandidates,
  }) {
    if (activeLabelId != null && !task.labelIds.contains(activeLabelId)) {
      return;
    }

    if (task.completedAt != null || task.isCompleted) {
      if (!pruneExpiredCompleted || _isWithinRetention(task, normalizedNow)) {
        completedList.add(task.copyWith(isCompleted: true));
      }
      return;
    }

    if (task.suspendedAt case final suspendedUntil?
        when suspendedUntil.isAfter(now)) {
      blockedList.add(task);
      return;
    }

    if (task.queuedAt == null) {
      somedayList.add(task);
      return;
    }

    if (_isTaskBlocked(
      task: task,
      unfinishedIds: unfinishedIds,
      labelMap: labelMap,
      evaluationTime: now,
      activeLabelId: activeLabelId,
      currentLatitude: currentLatitude,
      currentLongitude: currentLongitude,
    )) {
      blockedList.add(task);
      return;
    }

    activeCandidates.add(_IndexedTask(index: index, task: task));
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

  /// Collects the IDs of all open (unfinished) tasks in [tasks].
  static Set<String> _collectUnfinishedIds(List<TaskItem> tasks) {
    return <String>{
      for (final task in tasks)
        if (!task.isCompleted && task.completedAt == null) task.id,
    };
  }

  /// Compares two active tasks per `TDF_SPEC.md` Section 5.4 Step 2.
  static int _compareActiveCandidates(_IndexedTask first, _IndexedTask second) {
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

  /// Downgrades [task] from Tier 1 (`Focus`) to Tier 2 (`Ready`) per `TDF_SPEC.md` Section 6.3.
  TaskBoard _downgradeFromFocus(TaskItem task, DateTime now) {
    final totalActiveCount = focus.length + ready.length + planned.length;
    final nextFocus = _filterOutList(focus, task.id);
    final nextReady = List<TaskItem>.from(ready);
    final nextPlanned = List<TaskItem>.from(planned);

    _pullForFocusDowngrade(
      nextFocus: nextFocus,
      nextReady: nextReady,
      nextPlanned: nextPlanned,
    );

    if (totalActiveCount < focusSoftLimit + readySoftLimit) {
      final effectiveQueued = _resolveEndOfRegularQueueTimestamp(
        now,
        nextFocus,
        nextReady,
        nextPlanned,
      );
      final downgradedTask = task.toActive(
        isPriority: false,
        queuedAt: effectiveQueued,
      );
      if (nextFocus.length < focusSoftLimit) {
        nextFocus.add(downgradedTask);
      } else {
        nextReady.add(downgradedTask);
      }
    } else {
      final slot8Task = nextReady.last;
      final alignedPriority = slot8Task.isPriority;
      final slot8Queued = slot8Task.queuedAt ?? slot8Task.createdAt;
      final downgradedQueued = slot8Queued.add(const Duration(seconds: 1));
      nextReady.add(
        task.toActive(isPriority: alignedPriority, queuedAt: downgradedQueued),
      );
      _shiftCollidingPlannedTasks(
        nextPlanned,
        downgradedQueued,
        isPriorityGroup: alignedPriority,
      );
    }

    return copyWith(
      focus: nextFocus,
      ready: nextReady,
      planned: nextPlanned,
    ).pruneCompletedTasks(currentDate: now);
  }

  /// Downgrades [task] from Tier 2 (`Ready`) to Tier 3 (`Planned`) per `TDF_SPEC.md` Section 6.3.
  TaskBoard _downgradeToPlanned(TaskItem task, DateTime now) {
    final nextFocus = List<TaskItem>.from(focus);
    final nextReady = _filterOutList(ready, task.id);
    final nextPlanned = List<TaskItem>.from(planned);

    _cascadeQueues(
      nextFocus: nextFocus,
      nextReady: nextReady,
      nextPlanned: nextPlanned,
    );

    final effectiveQueued = _resolveEndOfRegularQueueTimestamp(
      now,
      nextFocus,
      nextReady,
      nextPlanned,
    );
    final downgradedTask = task.toActive(
      isPriority: false,
      queuedAt: effectiveQueued,
    );

    if (nextFocus.length < focusSoftLimit) {
      nextFocus.add(downgradedTask);
    } else if (nextReady.length < readySoftLimit) {
      nextReady.add(downgradedTask);
    } else {
      nextPlanned.add(downgradedTask);
    }

    return copyWith(
      focus: nextFocus,
      ready: nextReady,
      planned: nextPlanned,
    ).pruneCompletedTasks(currentDate: now);
  }

  /// Downgrades [task] from Tier 3 (`Planned`) to Tier 5 (`Someday`) per `TDF_SPEC.md` Section 6.3.
  TaskBoard _downgradeToSomeday(TaskItem task, DateTime now) {
    final nextPlanned = _filterOutList(planned, task.id);
    final downgradedTask = task.toActive(
      clearQueuedAt: true,
      isPriority: false,
    );

    return copyWith(
      planned: nextPlanned,
      someday: [...someday, downgradedTask],
    ).pruneCompletedTasks(currentDate: now);
  }

  /// Appends a numeric suffix (`_2`, `_3`, ...) if [baseId] already exists in [existingIds].
  static String _ensureUniqueContextId(String baseId, Set<String> existingIds) {
    if (!existingIds.contains(baseId)) {
      return baseId;
    }
    var suffix = 2;
    while (true) {
      final candidate = '${baseId}_$suffix';
      if (!existingIds.contains(candidate)) {
        return candidate;
      }
      suffix++;
    }
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

  /// Generates a sequential task ID (`t001`, `t002`, ...) that does not collide with existing tasks.
  String _generateUniqueTaskId() {
    final existingIds = <String>{for (final task in allTasks) task.id};
    var candidateNumber = existingIds.length + 1;
    while (true) {
      final candidate = 't${candidateNumber.toString().padLeft(3, '0')}';
      if (!existingIds.contains(candidate)) {
        return candidate;
      }
      candidateNumber++;
    }
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

  /// Evaluates whether [task] is blocked at [evaluationTime] per `TDF_SPEC.md` Section 5.3.
  ///
  /// An active `suspended` timestamp (`suspended > evaluationTime`) short-circuits
  /// immediately and disables evaluation of all other prerequisite and condition rules.
  static bool _isTaskBlocked({
    required TaskItem task,
    required Set<String> unfinishedIds,
    required Map<String, TdfLabel> labelMap,
    required DateTime evaluationTime,
    required String? activeLabelId,
    required double? currentLatitude,
    required double? currentLongitude,
  }) {
    if (task.suspendedAt case final suspendedUntil?
        when suspendedUntil.isAfter(evaluationTime)) {
      return true;
    }
    for (final prerequisiteId in task.blockedByTaskIds) {
      if (unfinishedIds.contains(prerequisiteId)) {
        return true;
      }
    }
    if (!_areTaskConditionsSatisfied(
      task: task,
      labelMap: labelMap,
      evaluationTime: evaluationTime,
      activeLabelId: activeLabelId,
      currentLatitude: currentLatitude,
      currentLongitude: currentLongitude,
    )) {
      return true;
    }
    return false;
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

  /// Normalizes active tasks across `[focus, ready, planned]` so `queuedAt` is always populated and ordered.
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
  }) {
    final nextFocus = List<TaskItem>.from(focus);
    final nextReady = List<TaskItem>.from(ready);
    final nextPlanned = List<TaskItem>.from(planned);
    _normalizeActiveLists(nextFocus, nextReady, nextPlanned);

    final nextBlocked = <TaskItem>[
      for (final task in blocked)
        task.copyWith(
          isCompleted: false,
          clearCompletedAt: true,
          queuedAt: task.queuedAt ?? task.createdAt,
          suspendedAt:
              (task.blockedByTaskIds.isEmpty &&
                  task.conditions.isEmpty &&
                  task.suspendedAt == null)
              ? TaskItem.defaultSuspendedAt
              : task.suspendedAt,
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

    return _NormalizedTierSlices(
      focus: nextFocus,
      ready: nextReady,
      planned: nextPlanned,
      blocked: nextBlocked,
      someday: nextSomeday,
      completed: nextCompleted,
    );
  }

  /// Pulls active tasks into [nextFocus] (up to 3) and [nextReady] (up to 4) before appending a downgraded `Focus` task.
  static void _pullForFocusDowngrade({
    required List<TaskItem> nextFocus,
    required List<TaskItem> nextReady,
    required List<TaskItem> nextPlanned,
  }) {
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

    var plannedForReadyIndex = 0;
    while (nextReady.length < readySoftLimit - 1 &&
        plannedForReadyIndex < nextPlanned.length) {
      nextReady.add(nextPlanned[plannedForReadyIndex].toActive());
      plannedForReadyIndex++;
    }
    if (plannedForReadyIndex > 0) {
      nextPlanned.removeRange(0, plannedForReadyIndex);
    }
  }

  /// Returns [task] without [labelId] in its `labelIds` list.
  static TaskItem _removeIdFromTaskLabels(TaskItem task, String labelId) {
    if (!task.labelIds.contains(labelId)) {
      return task;
    }
    return task.copyWith(
      labelIds: [
        for (final id in task.labelIds)
          if (id != labelId) id,
      ],
    );
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

  /// Resolves the `queued` timestamp for placing a downgraded task at the end of the regular FIFO queue.
  static DateTime _resolveEndOfRegularQueueTimestamp(
    DateTime now,
    List<TaskItem> focusList,
    List<TaskItem> readyList,
    List<TaskItem> plannedList,
  ) {
    DateTime? latestRegular;
    for (final item in [...focusList, ...readyList, ...plannedList]) {
      if (item.isPriority) {
        continue;
      }
      final itemQueued = item.queuedAt ?? item.createdAt;
      if (latestRegular == null || itemQueued.isAfter(latestRegular)) {
        latestRegular = itemQueued;
      }
    }
    if (latestRegular != null && !now.isAfter(latestRegular)) {
      return latestRegular.add(const Duration(seconds: 1));
    }
    return now;
  }

  /// Deduplicates and filters [candidateBlockedBy] for [taskId], rejecting self-dependencies
  /// and circular dependencies against the current board graph.
  List<String> _sanitizeBlockedByForTask(
    String taskId,
    List<String> candidateBlockedBy,
  ) {
    if (candidateBlockedBy.isEmpty) {
      return const [];
    }
    final sanitized = <String>[];
    for (final rawBlockerId in candidateBlockedBy) {
      final blockerId = rawBlockerId.trim();
      if (blockerId.isEmpty ||
          sanitized.contains(blockerId) ||
          wouldCreateDependencyCycle(taskId, blockerId)) {
        continue;
      }
      sanitized.add(blockerId);
    }
    return List<String>.unmodifiable(sanitized);
  }

  /// Deduplicates and canonicalizes [conditions] while enforcing `TDF_SPEC.md` Section 4.3 reset rules:
  /// - `condition any` supersedes all other task condition directives.
  /// - `day any`, `time any`, and `location any` supersede specific rules in their respective group.
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
    final mergedDays = <int>{};
    final timeRules = <TimeWindowTaskCondition>[];
    final locationRules = <LocationTaskCondition>[];

    for (final condition in conditions) {
      switch (condition) {
        case GlobalResetTaskCondition():
        case GroupResetTaskCondition():
          break;
        case DayTaskCondition(:final weekdays):
          if (!hasDayReset) {
            mergedDays.addAll(weekdays);
          }
        case TimeWindowTaskCondition():
          if (!hasTimeReset && !timeRules.contains(condition)) {
            timeRules.add(condition);
          }
        case LocationTaskCondition():
          if (!hasLocationReset && !locationRules.contains(condition)) {
            locationRules.add(condition);
          }
      }
    }

    return List<TaskCondition>.unmodifiable([
      if (hasDayReset)
        const GroupResetTaskCondition(targetGroup: ConditionGroup.day)
      else if (mergedDays.isNotEmpty)
        DayTaskCondition.fromWeekdays(mergedDays),
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

  /// Shifts colliding tasks in [plannedList] belonging to [isPriorityGroup] forward by `+00:00:01` per Section 6.3 Step 3.
  static void _shiftCollidingPlannedTasks(
    List<TaskItem> plannedList,
    DateTime minimumAfterQueued, {
    required bool isPriorityGroup,
  }) {
    var cursor = minimumAfterQueued;
    for (var i = 0; i < plannedList.length; i++) {
      final current = plannedList[i];
      if (current.isPriority != isPriorityGroup) {
        continue;
      }
      final currentQueued = current.queuedAt ?? current.createdAt;
      if (!currentQueued.isAfter(cursor)) {
        final shifted = cursor.add(const Duration(seconds: 1));
        plannedList[i] = current.copyWith(queuedAt: shifted);
        cursor = shifted;
      } else {
        cursor = currentQueued;
      }
    }
  }

  /// Slices sorted [activeCandidates] into `Focus` (`0..2`), `Ready` (`3..7`), and `Planned` (`>= 8`).
  static void _sliceActiveCandidates(
    List<_IndexedTask> activeCandidates, {
    required List<TaskItem> focusList,
    required List<TaskItem> readyList,
    required List<TaskItem> plannedList,
  }) {
    for (var i = 0; i < activeCandidates.length; i++) {
      final task = activeCandidates[i].task;
      if (i < focusSoftLimit) {
        focusList.add(task);
      } else if (i < focusSoftLimit + readySoftLimit) {
        readyList.add(task);
      } else {
        plannedList.add(task);
      }
    }
  }

  /// Builds a lowercase ASCII TDF entity identifier (`<prefix>_<slug>`) from [name].
  static String _slugifyContextName(String name, String prefix) {
    final buffer = StringBuffer();
    var lastWasSeparator = false;
    for (var i = 0; i < name.length; i++) {
      final unit = name.codeUnitAt(i);
      if (unit >= 0x41 && unit <= 0x5A) {
        buffer.writeCharCode(unit + 0x20);
        lastWasSeparator = false;
      } else if ((unit >= 0x61 && unit <= 0x7A) ||
          (unit >= 0x30 && unit <= 0x39)) {
        buffer.writeCharCode(unit);
        lastWasSeparator = false;
      } else if (buffer.isNotEmpty && !lastWasSeparator) {
        buffer.write('_');
        lastWasSeparator = true;
      }
    }
    var slug = buffer.toString();
    if (slug.endsWith('_')) {
      slug = slug.substring(0, slug.length - 1);
    }
    if (slug.isEmpty) {
      return '${prefix}001';
    }
    return '${prefix}_$slug';
  }

  /// Removes [labelId] from every task in [tasks].
  static List<TaskItem> _stripLabelFromTasks(
    List<TaskItem> tasks,
    String labelId,
  ) {
    return [for (final task in tasks) _removeIdFromTaskLabels(task, labelId)];
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
  });

  /// Normalized Tier 4 (`Blocked`) tasks.
  final List<TaskItem> blocked;

  /// Normalized Tier 6 (`Completed`) tasks.
  final List<TaskItem> completed;

  /// Normalized Tier 1 (`Focus`) tasks.
  final List<TaskItem> focus;

  /// Normalized Tier 3 (`Planned`) tasks.
  final List<TaskItem> planned;

  /// Normalized Tier 2 (`Ready`) tasks.
  final List<TaskItem> ready;

  /// Normalized Tier 5 (`Someday`) tasks.
  final List<TaskItem> someday;
}
