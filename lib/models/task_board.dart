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
    List<TdfLocation> locations = const [],
    List<TdfCategory> categories = const [],
  }) : this._normalized(
         _normalizeTierSlices(
           focus: focus,
           ready: ready,
           planned: planned,
           blocked: blocked,
           someday: someday,
           completed: completed,
         ),
         locations: locations,
         categories: categories,
       );

  TaskBoard._normalized(
    _NormalizedTierSlices slices, {
    required List<TdfLocation> locations,
    required List<TdfCategory> categories,
  }) : focus = List<TaskItem>.unmodifiable(slices.focus),
       ready = List<TaskItem>.unmodifiable(slices.ready),
       planned = List<TaskItem>.unmodifiable(slices.planned),
       blocked = List<TaskItem>.unmodifiable(slices.blocked),
       someday = List<TaskItem>.unmodifiable(slices.someday),
       completed = List<TaskItem>.unmodifiable(slices.completed),
       locations = List<TdfLocation>.unmodifiable(locations),
       categories = List<TdfCategory>.unmodifiable(categories);

  /// Creates an empty [TaskBoard] across all 6 tiers.
  factory TaskBoard.empty() => TaskBoard();

  /// Derives the 6 operational tiers from [tasks] in a single $O(N)$ pass per `TDF_SPEC.md` Section 5.
  factory TaskBoard.evaluate({
    required Iterable<TaskItem> tasks,
    DateTime? evaluationTime,
    List<TdfLocation> locations = const [],
    List<TdfCategory> categories = const [],
    String? activeCategoryId,
    String? activeLocationId,
    bool pruneExpiredCompleted = false,
  }) {
    final now = evaluationTime ?? DateTime.now().toUtc();
    final normalizedNow = DateTime.utc(now.year, now.month, now.day);
    final taskList = List<TaskItem>.from(tasks);
    final unfinishedIds = _collectUnfinishedIds(taskList);

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
        activeCategoryId: activeCategoryId,
        activeLocationId: activeLocationId,
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
      locations: locations,
      categories: categories,
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

  /// Defined TDF `category` blocks in declaration order.
  final List<TdfCategory> categories;

  /// Tier 6 (`Completed`) task items.
  final List<TaskItem> completed;

  /// Tier 1 (`Focus`) task items.
  final List<TaskItem> focus;

  /// Defined TDF `location` blocks in declaration order.
  final List<TdfLocation> locations;

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

  /// Adds a new TDF `category` block with a unique identifier and optional `#RRGGBB` [color].
  TaskBoard addCategory(
    String name, {
    String? color,
    String? id,
    String? note,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return this;
    }
    final existingIds = <String>{
      for (final category in categories) category.id,
    };
    final baseId = (id != null && id.trim().isNotEmpty)
        ? id.trim()
        : _slugifyContextName(trimmed, 'c');
    final categoryId = _ensureUniqueContextId(baseId, existingIds);
    final normalizedColor = TdfColor.normalizeHex(color);
    final newCategory = TdfCategory(
      id: categoryId,
      name: trimmed,
      color: normalizedColor,
      note: note,
    );
    return copyWith(categories: [...categories, newCategory]);
  }

  /// Adds a new TDF `location` block with a unique identifier and optional `#RRGGBB` [color].
  TaskBoard addLocation(
    String name, {
    String? color,
    String? id,
    String? note,
    double? latitude,
    double? longitude,
    double? radiusMeters,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return this;
    }
    final existingIds = <String>{for (final location in locations) location.id};
    final baseId = (id != null && id.trim().isNotEmpty)
        ? id.trim()
        : _slugifyContextName(trimmed, 'l');
    final locationId = _ensureUniqueContextId(baseId, existingIds);
    final normalizedColor = TdfColor.normalizeHex(color);
    final newLocation = TdfLocation(
      id: locationId,
      name: trimmed,
      color: normalizedColor,
      note: note,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
    );
    return copyWith(locations: [...locations, newLocation]);
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
    List<String> locationIds = const [],
    List<String> categoryIds = const [],
  }) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return this;
    }

    final now = currentDate ?? DateTime.now().toUtc();
    final effectivePriority = isPriority || targetTier == TaskTier.focus;
    final cleanSubtasks = _cleanSubtasks(subtasks);
    final autoCompleted =
        subtasksAutoFinish &&
        cleanSubtasks.isNotEmpty &&
        cleanSubtasks.every((step) => step.isCompleted);
    final isDone = targetTier == TaskTier.completed || autoCompleted;
    final isSomeday = targetTier == TaskTier.someday && !isDone;
    final isBlocked = targetTier == TaskTier.blocked && !isDone;
    final taskId = id ?? _generateUniqueTaskId();

    final newTask = TaskItem(
      id: taskId,
      title: trimmed,
      note: note,
      isCompleted: isDone,
      isPriority: effectivePriority && !isSomeday && !isBlocked,
      createdAt: now,
      queuedAt: isSomeday ? null : now,
      completedAt: isDone ? now : null,
      suspendedAt: isBlocked ? TaskItem.defaultSuspendedAt : null,
      locationIds: locationIds,
      categoryIds: categoryIds,
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
      locations: locations,
      categories: categories,
      pruneExpiredCompleted: true,
    );
  }

  /// Evaluates the active pull cycle and unblocks any tasks whose prerequisites or deferrals cleared.
  TaskBoard applyAutoPull({DateTime? currentDate}) {
    final now = currentDate ?? DateTime.now().toUtc();
    final unfinishedIds = _collectUnfinishedIds(allTasks);
    final nextFocus = List<TaskItem>.from(focus);
    final nextReady = List<TaskItem>.from(ready);
    final nextPlanned = List<TaskItem>.from(planned);
    final nextBlocked = <TaskItem>[];

    for (final task in blocked) {
      if (_isTaskBlocked(task, unfinishedIds, now)) {
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
    List<TdfLocation>? locations,
    List<TdfCategory>? categories,
  }) {
    return TaskBoard(
      focus: focus ?? this.focus,
      ready: ready ?? this.ready,
      planned: planned ?? this.planned,
      blocked: blocked ?? this.blocked,
      someday: someday ?? this.someday,
      completed: completed ?? this.completed,
      locations: locations ?? this.locations,
      categories: categories ?? this.categories,
    );
  }

  /// Deletes the category with [categoryId] and removes its reference from all tasks.
  TaskBoard deleteCategory(String categoryId) {
    final nextCategories = <TdfCategory>[
      for (final category in categories)
        if (category.id != categoryId) category,
    ];
    if (nextCategories.length == categories.length) {
      return this;
    }
    return copyWith(
      focus: _stripCategoryFromTasks(focus, categoryId),
      ready: _stripCategoryFromTasks(ready, categoryId),
      planned: _stripCategoryFromTasks(planned, categoryId),
      blocked: _stripCategoryFromTasks(blocked, categoryId),
      someday: _stripCategoryFromTasks(someday, categoryId),
      completed: _stripCategoryFromTasks(completed, categoryId),
      categories: nextCategories,
    );
  }

  /// Deletes the location with [locationId] and removes its reference from all tasks.
  TaskBoard deleteLocation(String locationId) {
    final nextLocations = <TdfLocation>[
      for (final location in locations)
        if (location.id != locationId) location,
    ];
    if (nextLocations.length == locations.length) {
      return this;
    }
    return copyWith(
      focus: _stripLocationFromTasks(focus, locationId),
      ready: _stripLocationFromTasks(ready, locationId),
      planned: _stripLocationFromTasks(planned, locationId),
      blocked: _stripLocationFromTasks(blocked, locationId),
      someday: _stripLocationFromTasks(someday, locationId),
      completed: _stripLocationFromTasks(completed, locationId),
      locations: nextLocations,
    );
  }

  /// Downgrades a task one active tier down per `TDF_SPEC.md` Section 6.3 and Section 6.4,
  /// stripping the `priority` flag and updating `queued` to prevent ping-pong bounce.
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

    final demoted = task.toActive(isPriority: false);
    if (sourceTier == TaskTier.focus) {
      return _downgradeFromFocus(demoted, now);
    }
    if (sourceTier == TaskTier.ready) {
      return _downgradeFromReady(demoted, now);
    }
    return this;
  }

  /// Derives a filtered [TaskBoard] considering only active tasks matching
  /// [activeCategoryId] and [activeLocationId] while preserving all other
  /// `TDF_SPEC.md` Section 5 evaluation rules.
  TaskBoard evaluateForContext({
    String? activeCategoryId,
    String? activeLocationId,
    DateTime? evaluationTime,
  }) {
    return TaskBoard.evaluate(
      tasks: allTasks,
      evaluationTime: evaluationTime,
      locations: locations,
      categories: categories,
      activeCategoryId: activeCategoryId,
      activeLocationId: activeLocationId,
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
    required String? activeCategoryId,
    required String? activeLocationId,
    required bool pruneExpiredCompleted,
    required List<TaskItem> completedList,
    required List<TaskItem> somedayList,
    required List<TaskItem> blockedList,
    required List<_IndexedTask> activeCandidates,
  }) {
    if (task.completedAt != null || task.isCompleted) {
      if (!pruneExpiredCompleted || _isWithinRetention(task, normalizedNow)) {
        completedList.add(task.copyWith(isCompleted: true));
      }
      return;
    }

    if (task.queuedAt == null) {
      somedayList.add(task);
      return;
    }

    if (_isTaskBlocked(task, unfinishedIds, now)) {
      blockedList.add(task);
      return;
    }

    if (!_matchesContextFilters(task, activeCategoryId, activeLocationId)) {
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

  /// Downgrades [task] from Tier 1 (`Focus`) to the end of Tier 2 (`Ready`) per Section 6.4.
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

    final referenceQueued = nextReady.isNotEmpty
        ? (nextReady.last.queuedAt ?? now)
        : (nextFocus.isNotEmpty ? (nextFocus.last.queuedAt ?? now) : now);
    nextReady.add(
      task.copyWith(
        isPriority: false,
        queuedAt: referenceQueued.add(const Duration(minutes: 1)),
      ),
    );

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

  /// Downgrades [task] from Tier 2 (`Ready`) to Tier 3 (`Planned`) per Section 6.3.
  TaskBoard _downgradeFromReady(TaskItem task, DateTime now) {
    final nextFocus = List<TaskItem>.from(focus);
    final nextReady = _filterOutList(ready, task.id);
    final nextPlanned = List<TaskItem>.from(planned);

    _cascadeQueues(
      nextFocus: nextFocus,
      nextReady: nextReady,
      nextPlanned: nextPlanned,
    );
    nextPlanned.add(task.copyWith(isPriority: false, queuedAt: now));

    return copyWith(
      focus: nextFocus,
      ready: nextReady,
      planned: nextPlanned,
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

  /// Evaluates whether [task] is blocked at [evaluationTime] per `TDF_SPEC.md` Section 5.3.
  static bool _isTaskBlocked(
    TaskItem task,
    Set<String> unfinishedIds,
    DateTime evaluationTime,
  ) {
    for (final prerequisiteId in task.blockedByTaskIds) {
      if (unfinishedIds.contains(prerequisiteId)) {
        return true;
      }
    }
    if (task.suspendedAt case final suspendedUntil?) {
      if (suspendedUntil.isAfter(evaluationTime)) {
        return true;
      }
    }
    for (final condition in task.conditions) {
      if (!condition.isSatisfiedAt(evaluationTime)) {
        return true;
      }
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

  /// Evaluates whether [task] matches the optional [activeCategoryId] and [activeLocationId] filters.
  static bool _matchesContextFilters(
    TaskItem task,
    String? activeCategoryId,
    String? activeLocationId,
  ) {
    if (activeCategoryId != null &&
        !task.categoryIds.contains(activeCategoryId)) {
      return false;
    }
    if (activeLocationId != null &&
        task.locationIds.isNotEmpty &&
        !task.locationIds.contains(activeLocationId)) {
      return false;
    }
    return true;
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

  /// Returns [task] without [categoryId] in its `categoryIds` list.
  static TaskItem _removeIdFromTaskCategories(
    TaskItem task,
    String categoryId,
  ) {
    if (!task.categoryIds.contains(categoryId)) {
      return task;
    }
    return task.copyWith(
      categoryIds: [
        for (final id in task.categoryIds)
          if (id != categoryId) id,
      ],
    );
  }

  /// Returns [task] without [locationId] in its `locationIds` list.
  static TaskItem _removeIdFromTaskLocations(TaskItem task, String locationId) {
    if (!task.locationIds.contains(locationId)) {
      return task;
    }
    return task.copyWith(
      locationIds: [
        for (final id in task.locationIds)
          if (id != locationId) id,
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

  /// Removes [categoryId] from every task in [tasks].
  static List<TaskItem> _stripCategoryFromTasks(
    List<TaskItem> tasks,
    String categoryId,
  ) {
    return [
      for (final task in tasks) _removeIdFromTaskCategories(task, categoryId),
    ];
  }

  /// Removes [locationId] from every task in [tasks].
  static List<TaskItem> _stripLocationFromTasks(
    List<TaskItem> tasks,
    String locationId,
  ) {
    return [
      for (final task in tasks) _removeIdFromTaskLocations(task, locationId),
    ];
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
