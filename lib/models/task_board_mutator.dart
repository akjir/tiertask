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
import 'task_board_evaluator.dart';
import 'task_board_queue_mutator.dart';
import 'task_item.dart';
import 'task_tier.dart';
import 'tdf_error.dart';
import 'tdf_location.dart';
import 'tdf_metadata.dart';
import 'tdf_sync_metadata.dart';
import 'tdf_timezone.dart';

/// Label and location lookup and duplicate validation helpers on [NormalizedTierSlices].
extension TaskBoardMutationSlicesX on NormalizedTierSlices {
  /// Finds the [TdfLabel] with [labelId], or `null` if not found.
  TdfLabel? findLabel(String labelId) {
    for (final label in labels) {
      if (label.id == labelId) return label;
    }
    return null;
  }

  /// Finds the [TdfLocation] with [locationId], or `null` if not found.
  TdfLocation? findLocation(String locationId) {
    for (final location in locations) {
      if (location.id == locationId) return location;
    }
    return null;
  }

  /// Returns whether any label on the board (excluding [excludingLabelId]) already uses [name].
  bool hasDuplicateLabelName(String name, {String? excludingLabelId}) {
    final target = name.trim().toLowerCase();
    return target.isNotEmpty &&
        labels.any(
          (item) =>
              item.id != excludingLabelId &&
              item.name.trim().toLowerCase() == target,
        );
  }

  /// Returns whether any task on the board (excluding [excludingTaskId]) already uses [title].
  bool hasDuplicateTaskTitle(String title, {String? excludingTaskId}) {
    final target = title.trim().toLowerCase();
    return target.isNotEmpty &&
        allTasks.any(
          (item) =>
              item.id != excludingTaskId &&
              item.title.trim().toLowerCase() == target,
        );
  }
}

/// Stateless task, subtask, label CRUD, prerequisite arming, and recurrence
/// mutation engine per `TDF_SPEC.md` Sections 6.1, 6.4, and 6.8–6.10.
@immutable
class TaskBoardMutator {
  /// Private constructor for static task and label mutation helpers.
  const TaskBoardMutator._();

  /// Adds a new TDF `label` block to [board] with a unique identifier and optional `#RRGGBB` [color].
  static NormalizedTierSlices addLabel(
    NormalizedTierSlices board,
    String name, {
    String? color,
    String? id,
    String? note,
    bool isScoped = false,
    DateTime? currentDate,
    DateTime? modifiedAt,
    List<TaskCondition> conditions = const [],
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return board;
    final rawTime = modifiedAt ?? currentDate;
    final stamp = rawTime != null ? TaskItem.normalizeTimestamp(rawTime) : null;
    final used = _collectAllUsedEntityIds(board);
    final labelId =
        _trimOrNull(id) ?? generateLabelId(timestamp: stamp, existingIds: used);
    if (board.findLabel(labelId) != null ||
        board.deletedBlock.findLabelRecord(labelId) != null) {
      return board;
    }
    final newLabel = TdfLabel(
      id: labelId,
      name: trimmed,
      isScoped: isScoped,
      color: TdfColor.normalizeHex(color),
      note: _trimOrNull(note),
      modifiedAt: stamp,
      conditions: _sanitizeLabelRules(conditions) ?? const [],
    );
    return board
        .copyWithSlices(labels: [...board.labels, newLabel])
        .logDomainMutation('addLabel id=$labelId name="$trimmed"');
  }

  /// Adds a new TDF `location` block to [board] with a unique identifier per `TDF_SPEC_0.6.0.md` Section 4.3 and 6.1.
  static NormalizedTierSlices addLocation(
    NormalizedTierSlices board,
    String name, {
    required double latitude,
    required double longitude,
    required double radius,
    String? id,
    String? note,
    String? source,
    DateTime? currentDate,
    DateTime? modifiedAt,
  }) {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty ||
        !latitude.isFinite ||
        latitude < -90.0 ||
        latitude > 90.0 ||
        !longitude.isFinite ||
        longitude < -180.0 ||
        longitude > 180.0 ||
        !radius.isFinite ||
        radius <= 0.0 ||
        radius > maxTdfLocationRadius ||
        board.locations.length >= maxTdfLocations) {
      return board;
    }
    final rawTime = modifiedAt ?? currentDate;
    final stamp = rawTime != null ? TaskItem.normalizeTimestamp(rawTime) : null;
    final used = _collectAllUsedEntityIds(board);
    final locationId =
        _trimOrNull(id) ??
        generateLocationId(timestamp: stamp, existingIds: used);
    if (board.findLocation(locationId) != null ||
        board.deletedBlock.findLocationRecord(locationId) != null) {
      return board;
    }
    final newLocation = TdfLocation(
      id: locationId,
      name: trimmedName,
      latitude: latitude,
      longitude: longitude,
      radius: radius,
      note: _trimOrNull(note),
      source: _trimOrNull(source),
      modifiedAt: stamp,
    );
    return board
        .copyWithSlices(locations: [...board.locations, newLocation])
        .logDomainMutation('addLocation id=$locationId');
  }

  /// Validates [title], allocates a task ID when [id] is `null`, and runs [mutate].
  static NormalizedTierSlices addTask(
    NormalizedTierSlices board,
    String title, {
    String? id,
    DateTime? currentDate,
    required NormalizedTierSlices Function(String taskId, DateTime now) mutate,
  }) {
    final trimmed = title.trim();
    if (trimmed.isEmpty || board.hasDuplicateTaskTitle(trimmed)) return board;
    final now = _resolveNow(currentDate);
    final used = _collectAllUsedEntityIds(board);
    return mutate(id ?? generateTaskId(timestamp: now, existingIds: used), now);
  }

  /// Marks an active task on [board] as done per `TDF_SPEC.md` Sections 6.4 and 6.9.4.
  static NormalizedTierSlices completeTask(
    NormalizedTierSlices board,
    String taskId, {
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    int? expectedCompletions,
  }) {
    final now = _resolveNow(currentDate);
    final task = board.findTask(taskId);
    final isDone = task == null || task.isCompleted || task.completedAt != null;
    if (isDone ||
        (expectedCompletions ?? task.completions) != task.completions) {
      return board;
    }
    if (task.completions >= TdfTaskDependency.maxCompletions) {
      throw const FormatException('LimitExceeded');
    }
    final zone = _zone(now, localEvaluationTime, timeZone);
    final next = _reschedule(board, task, now, zone);
    final nextQueue = TaskBoardQueueMutator.updateQueueForEditedTask(
      board.queueBlock,
      task,
      next ?? task,
      next != null,
      now,
    );
    final nextTasks = next != null
        ? board.allTasks.map((item) => item.id == taskId ? next : item)
        : [
            task.toCompleted(now),
            ...board.allTasks.where((item) => item.id != taskId),
          ];
    final suffix = next != null ? ' (recurring)' : '';
    return TaskBoardEvaluator.reevaluateBoard(
      board,
      tasks: nextTasks,
      queueBlock: nextQueue,
      now: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
    ).logDomainMutation('completeTask$suffix id=$taskId');
  }

  /// Deletes the label with [labelId] from [board], removes its reference from all tasks (applying `scoped` global-view flood protection per Section 6.8.1), and records the deletion.
  static NormalizedTierSlices deleteLabel(
    NormalizedTierSlices board,
    String labelId, [
    DateTime? currentDate,
  ]) {
    final prior = board.findLabel(labelId);
    if (prior == null) return board;
    final now = _resolveNow(currentDate);
    final stamp = TaskItem.nextModifiedTimestamp(
      now,
      prior.effectiveModifiedAt,
    );
    final record = TdfDeletedLabelRecord(labelId: labelId, deletedAt: stamp);
    final labelMap = <String, TdfLabel>{
      for (final label in board.labels) label.id: label,
    };
    final evictedQueueIds = <String>{};
    final updatedTasks = <TaskItem>[];
    for (final task in board.allTasks) {
      if (!task.labelIds.contains(labelId)) {
        updatedTasks.add(task);
        continue;
      }
      final wasRestricted = TaskBoardEvaluator.isRestrictedFromGlobalView(
        task,
        labelMap,
      );
      final remainingLabels = task.labelIds
          .where((id) => id != labelId)
          .toList();
      final lostAllScopedLabels = wasRestricted && remainingLabels.isEmpty;
      if (lostAllScopedLabels && board.queueBlock.taskIds.contains(task.id)) {
        evictedQueueIds.add(task.id);
      }
      updatedTasks.add(
        task.copyWith(
          labelIds: remainingLabels,
          isPriority: lostAllScopedLabels ? false : task.isPriority,
          modifiedAt: TaskItem.nextModifiedTimestamp(
            now,
            task.effectiveModifiedAt,
          ),
        ),
      );
    }
    var nextQueueBlock = board.queueBlock;
    for (final evictedId in evictedQueueIds) {
      nextQueueBlock = TaskBoardQueueMutator.removeTaskFromQueue(
        nextQueueBlock,
        evictedId,
        now,
      );
    }
    return TaskBoardEvaluator.reevaluateBoard(
      board,
      tasks: updatedTasks,
      labels: board.labels.where((item) => item.id != labelId).toList(),
      deletedBlock: TaskBoardEvaluator.recordLabelDeletion(
        board.deletedBlock,
        record,
      ),
      queueBlock: nextQueueBlock,
      now: now,
      pruneExpiredCompleted: false,
    ).logDomainMutation('deleteLabel id=$labelId');
  }

  /// Deletes the location with [locationId] from [board] in strict `label`-before-`task` order (applying `condition location any` inheritance-trap protection per Section 6.8.1) and records the deletion.
  static NormalizedTierSlices deleteLocation(
    NormalizedTierSlices board,
    String locationId, {
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  }) {
    final prior = board.findLocation(locationId);
    if (prior == null) return board;
    final now = _resolveNow(currentDate);
    final stamp = TaskItem.nextModifiedTimestamp(
      now,
      prior.effectiveModifiedAt,
    );
    final record = TdfDeletedLocationRecord(
      locationId: locationId,
      deletedAt: stamp,
    );
    final updatedLabels = <TdfLabel>[
      for (final label in board.labels)
        _cascadeLocationDeletionOnLabel(label, locationId, now),
    ];
    final postCascadeLabelsWithLocation = <String>{
      for (final label in updatedLabels)
        if (_hasLocationConditionRule(label.conditions)) label.id,
    };
    final updatedTasks = <TaskItem>[
      for (final task in board.allTasks)
        _cascadeLocationDeletionOnTask(
          task,
          locationId,
          postCascadeLabelsWithLocation,
          now,
        ),
    ];
    final remainingLocations = board.locations
        .where((item) => item.id != locationId)
        .toList();
    return TaskBoardEvaluator.reevaluateBoard(
      board,
      tasks: updatedTasks,
      labels: updatedLabels,
      locations: remainingLocations,
      deletedBlock: TaskBoardEvaluator.recordLocationDeletion(
        board.deletedBlock,
        record,
      ),
      now: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      pruneExpiredCompleted: false,
    ).logDomainMutation('deleteLocation id=$locationId');
  }

  /// Deletes the task with [taskId] from [board], removes its `queue` entry, and records the deletion in `deletedBlock`.
  static NormalizedTierSlices deleteTask(
    NormalizedTierSlices board,
    String taskId, {
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  }) {
    final prior = board.findTask(taskId);
    if (prior == null) return board;
    final now = _resolveNow(currentDate);
    final stamp = TaskItem.nextModifiedTimestamp(
      now,
      prior.effectiveModifiedAt,
    );
    final record = TdfDeletedTaskRecord(
      taskId: taskId,
      deletedAt: stamp,
      completionsCheckpoint: prior.completions,
    );
    return TaskBoardEvaluator.reevaluateBoard(
      board,
      tasks: board.allTasks.where((item) => item.id != taskId),
      deletedBlock: TaskBoardEvaluator.recordTaskDeletion(
        board.deletedBlock,
        record,
      ),
      queueBlock: TaskBoardQueueMutator.removeTaskFromQueue(
        board.queueBlock,
        taskId,
        now,
      ),
      now: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
    ).logDomainMutation('deleteTask id=$taskId');
  }

  /// Toggles the subtask step at [stepIndex] on [taskId] in [board], auto-completing the task when `subtasks auto-finish` is enabled.
  static NormalizedTierSlices toggleSubtask(
    NormalizedTierSlices board,
    String taskId,
    int stepIndex, {
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  }) {
    final now = _resolveNow(currentDate);
    final tier = board.findTierOfTask(taskId);
    final task = board.findTask(taskId);
    final isDone = task == null || task.isCompleted || task.completedAt != null;
    if (tier == null || tier == TaskTier.completed || isDone) return board;
    if (stepIndex < 0 || stepIndex >= task.subtasks.length) return board;
    final targetStep = task.subtasks[stepIndex];
    final toggled = targetStep.copyWith(isCompleted: !targetStep.isCompleted);
    final steps = <SubtaskItem>[
      for (var i = 0; i < task.subtasks.length; i++)
        i == stepIndex ? toggled : task.subtasks[i],
    ];
    final willAutoComplete = _allStepsDone(task.subtasksAutoFinish, steps);
    final nextModified = willAutoComplete
        ? task.modifiedAt
        : TaskItem.nextModifiedTimestamp(now, task.effectiveModifiedAt);
    final updated = task.copyWith(subtasks: steps, modifiedAt: nextModified);
    final replaced = _mapBoardTasks(
      board,
      (item) => item.id == taskId ? updated : item,
    );
    final logMessage = 'toggleSubtask id=$taskId step=$stepIndex';
    if (!willAutoComplete) return replaced.logDomainMutation(logMessage);
    return completeTask(
      replaced,
      taskId,
      currentDate: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
    ).logDomainMutation('$logMessage (auto-completed)');
  }

  /// Updates an existing label with [labelId] on [board], re-evaluates the 6-tier pipeline, and ignores empty/duplicate names.
  static NormalizedTierSlices updateLabel(
    NormalizedTierSlices board,
    String labelId, {
    String? name,
    bool? isScoped,
    String? color,
    bool clearColor = false,
    String? note,
    bool clearNote = false,
    List<TaskCondition>? conditions,
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  }) {
    final prior = board.findLabel(labelId);
    if (prior == null) return board;
    final trimmedName = (name ?? prior.name).trim();
    if (trimmedName.isEmpty ||
        board.hasDuplicateLabelName(trimmedName, excludingLabelId: labelId)) {
      return board;
    }
    final now = _resolveNow(currentDate);
    final normalizedColor = TdfColor.normalizeHex(color);
    final cleanNote = _trimOrNull(note);
    final stamp = TaskItem.nextModifiedTimestamp(
      now,
      prior.effectiveModifiedAt,
    );
    final updatedLabel = prior.copyWith(
      name: trimmedName,
      isScoped: isScoped,
      color: normalizedColor,
      clearColor: clearColor || (color != null && normalizedColor == null),
      note: cleanNote,
      clearNote: clearNote || (note != null && cleanNote == null),
      conditions: _sanitizeLabelRules(conditions),
      modifiedAt: stamp,
    );
    final logMessage =
        'updateLabel/renameLabel id=$labelId name="$trimmedName"';
    return TaskBoardEvaluator.reevaluateBoard(
      board,
      labels: [
        for (final item in board.labels)
          item.id == labelId ? updatedLabel : item,
      ],
      now: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
    ).logDomainMutation(logMessage);
  }

  /// Updates an existing location with [locationId] on [board] per `TDF_SPEC_0.6.0.md` Section 4.3 and 6.6.
  static NormalizedTierSlices updateLocation(
    NormalizedTierSlices board,
    String locationId, {
    String? name,
    double? latitude,
    double? longitude,
    double? radius,
    String? note,
    bool clearNote = false,
    String? source,
    bool clearSource = false,
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  }) {
    final prior = board.findLocation(locationId);
    if (prior == null) return board;
    final trimmedName = (name ?? prior.name).trim();
    final nextLatitude = latitude ?? prior.latitude;
    final nextLongitude = longitude ?? prior.longitude;
    final nextRadius = radius ?? prior.radius;
    if (trimmedName.isEmpty ||
        !nextLatitude.isFinite ||
        nextLatitude < -90.0 ||
        nextLatitude > 90.0 ||
        !nextLongitude.isFinite ||
        nextLongitude < -180.0 ||
        nextLongitude > 180.0 ||
        !nextRadius.isFinite ||
        nextRadius <= 0.0 ||
        nextRadius > maxTdfLocationRadius) {
      return board;
    }
    final now = _resolveNow(currentDate);
    final cleanNote = _trimOrNull(note);
    final cleanSource = _trimOrNull(source);
    final stamp = TaskItem.nextModifiedTimestamp(
      now,
      prior.effectiveModifiedAt,
    );
    final updatedLocation = prior.copyWith(
      name: trimmedName,
      latitude: nextLatitude,
      longitude: nextLongitude,
      radius: nextRadius,
      note: cleanNote,
      clearNote: clearNote || (note != null && cleanNote == null),
      source: cleanSource,
      clearSource: clearSource || (source != null && cleanSource == null),
      modifiedAt: stamp,
    );
    return TaskBoardEvaluator.reevaluateBoard(
      board,
      locations: [
        for (final item in board.locations)
          item.id == locationId ? updatedLocation : item,
      ],
      now: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
    ).logDomainMutation('updateLocation id=$locationId');
  }

  /// Updates an existing task (or creates a new task when [isNewTask] is `true`) with [taskId] on [board].
  static NormalizedTierSlices updateTask(
    NormalizedTierSlices board,
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
    DateTime? dueAt,
    bool clearDueAt = false,
    TaskRepeatRule? repeatRule,
    bool clearRepeatRule = false,
    List<String>? blockedByTaskIds,
    List<TdfTaskDependency>? dependencies,
    TaskOrigin? origin,
    bool clearOrigin = false,
    List<TaskLink>? links,
    List<TaskCondition>? conditions,
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    DateTime? modifiedAt,
    bool isNewTask = false,
  }) {
    final prior = isNewTask ? null : board.findTask(taskId);
    if (!isNewTask && prior == null) return board;
    final trimmed = (title ?? prior?.title ?? '').trim();
    if (trimmed.isEmpty ||
        board.hasDuplicateTaskTitle(trimmed, excludingTaskId: taskId)) {
      return board;
    }
    final now = _resolveNow(currentDate);
    final wasDone = (prior?.isCompleted ?? false) || prior?.completedAt != null;
    final isTargetDone = targetTier == TaskTier.completed;
    final isRestoring = wasDone && targetTier != null && !isTargetDone;
    final autoFinish = subtasksAutoFinish ?? prior?.subtasksAutoFinish ?? false;
    final steps = subtasks != null
        ? _cleanSubtasks(subtasks)
        : (prior?.subtasks ?? const <SubtaskItem>[]);
    final repeat = clearRepeatRule ? null : (repeatRule ?? prior?.repeatRule);
    final autoDone = !isRestoring && _allStepsDone(autoFinish, steps);
    final isRecurringAuto = autoDone && !isTargetDone && repeat != null;
    final keepDone = targetTier == null && wasDone;
    final isDone = isTargetDone || keepDone || (autoDone && !isRecurringAuto);
    final isBlockedTarget = !isDone && targetTier == TaskTier.blocked;
    final isSomedayTarget = targetTier == TaskTier.someday;
    final clearDefer =
        isDone ||
        clearSuspendedAt ||
        isRestoring ||
        (isSomedayTarget && suspendedAt == null && isSuspendedForever != true);
    final keepForever =
        (prior?.isSuspendedForever ?? false) ||
        (isBlockedTarget && prior?.suspendedAt == null);
    final autoForever =
        suspendedAt == TaskItem.defaultSuspendedAt ||
        (suspendedAt == null && keepForever);
    final isForever = !clearDefer && (isSuspendedForever ?? autoForever);
    final rawSuspended = suspendedAt ?? prior?.suspendedAt;
    final nextSuspended = (clearDefer || isForever) ? null : rawSuspended;
    final isDeferred = isForever || (nextSuspended?.isAfter(now) ?? false);
    final wasQueued =
        prior == null || board.queueBlock.taskIds.contains(taskId);
    final unqueuedEdit = targetTier == null && !wasQueued;
    final isSomeday =
        !isDone && !isDeferred && (isSomedayTarget || unqueuedEdit);
    final basePriority = isRestoring ? false : (prior?.isPriority ?? false);
    final allowPriority = !isBlockedTarget || isDeferred || repeat != null;
    final isFocus =
        (isPriority ?? basePriority) || targetTier == TaskTier.focus;
    final nextPriority = !isSomeday && allowPriority && isFocus;
    final stamp = prior != null
        ? TaskItem.nextModifiedTimestamp(now, prior.effectiveModifiedAt)
        : TaskItem.normalizeTimestamp(modifiedAt ?? now);
    final prevCount = prior?.completions ?? 0;
    final armed = _armDeps(
      board,
      taskId,
      blockedByTaskIds,
      dependencies,
      prior,
    );
    final nextDueAt = (clearDueAt || (isRestoring && dueAt == null))
        ? null
        : (dueAt ?? prior?.dueAt);
    final nextOrigin = clearOrigin ? null : (origin ?? prior?.origin);
    final baseTask = TaskItem(
      id: taskId,
      title: trimmed,
      note: note != null ? _trimOrNull(note) : prior?.note,
      isCompleted: isDone,
      completions: (isDone && !wasDone) ? prevCount + 1 : prevCount,
      isPriority: nextPriority,
      createdAt: prior?.createdAt ?? now,
      completedAt: isDone ? (prior?.completedAt ?? now) : null,
      modifiedAt: stamp,
      suspendedAt: nextSuspended,
      isSuspendedForever: isForever,
      dueAt: nextDueAt,
      repeatRule: repeat,
      dependencies: isRestoring
          ? TaskBoardQueueMutator.rearmDependencies(board, armed)
          : armed,
      labelIds: labelIds ?? prior?.labelIds ?? const [],
      origin: nextOrigin,
      links: links != null ? _cleanLinks(links) : (prior?.links ?? const []),
      conditions: _sanitizeTaskRules(conditions, prior?.conditions ?? const []),
      subtasksAutoFinish: autoFinish,
      subtasks: (isRestoring || isDone)
          ? TaskBoardQueueMutator.setAllSubtasksCompleted(steps, isDone)
          : steps,
    );
    final zone = _zone(now, localEvaluationTime, timeZone);
    final finalTask = isRecurringAuto
        ? (_reschedule(board, baseTask, now, zone, stamp) ?? baseTask)
        : baseTask;
    final nextQueue = TaskBoardQueueMutator.updateQueueForEditedTask(
      board.queueBlock,
      prior,
      finalTask,
      isRecurringAuto || (!isDone && !isSomeday),
      now,
    );
    final added = isDone
        ? [finalTask, ...board.allTasks]
        : [...board.allTasks, finalTask];
    final nextTasks = prior != null
        ? board.allTasks.map((item) => item.id == taskId ? finalTask : item)
        : added;
    final action = isNewTask ? 'addTask' : 'updateTask';
    return TaskBoardEvaluator.reevaluateBoard(
      board,
      tasks: nextTasks,
      queueBlock: nextQueue,
      now: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
    ).logDomainMutation('$action id=$taskId title="$trimmed"');
  }

  /// Returns whether [autoFinish] is enabled and [steps] is non-empty with all steps completed.
  static bool _allStepsDone(bool autoFinish, List<SubtaskItem> steps) =>
      autoFinish && steps.isNotEmpty && steps.every((step) => step.isCompleted);

  /// Arms prerequisite requirements for [taskId] on [board] per `TDF_SPEC.md` Section 6.9.3.
  static List<TdfTaskDependency> _armDeps(
    NormalizedTierSlices board,
    String taskId,
    List<String>? blockedIds,
    List<TdfTaskDependency>? explicitDeps,
    TaskItem? prior,
  ) {
    if (prior != null && blockedIds == null && explicitDeps == null) {
      return prior.dependencies;
    }
    final seen = <String>{};
    bool allow(String id) =>
        id.isNotEmpty &&
        seen.add(id) &&
        !TaskBoardEvaluator.wouldCreateDependencyCycle(board, taskId, id);
    final priorMap = <String, int>{
      for (final item in prior?.dependencies ?? const <TdfTaskDependency>[])
        item.taskId: item.requiredCompletion,
    };
    final trimmedIds = (blockedIds ?? const <String>[]).map((s) => s.trim());
    final items = explicitDeps != null
        ? [
            for (final dep in explicitDeps)
              if (allow(dep.taskId.trim())) dep,
          ]
        : [
            for (final id in trimmedIds)
              if (allow(id))
                TdfTaskDependency(
                  taskId: id,
                  requiredCompletion:
                      priorMap[id] ??
                      TaskBoardQueueMutator.captureDependencyRequirement(
                        board.findTask(id),
                      ),
                ),
          ];
    return List<TdfTaskDependency>.unmodifiable(items);
  }

  /// Removes [deletedLocationId] from [label]'s location conditions and advances `label.modified` if changed per Section 6.8.1.
  static TdfLabel _cascadeLocationDeletionOnLabel(
    TdfLabel label,
    String deletedLocationId,
    DateTime now,
  ) {
    if (!_referencesLocationId(label.conditions, deletedLocationId)) {
      return label;
    }
    final nextConditions = <TaskCondition>[];
    for (final rule in label.conditions) {
      if (rule is! LocationTaskCondition) {
        nextConditions.add(rule);
        continue;
      }
      final remainingIds = rule.locationIds
          .where((id) => id != deletedLocationId)
          .toList();
      if (remainingIds.isNotEmpty) {
        nextConditions.add(LocationTaskCondition.fromIds(remainingIds));
      }
    }
    return label.copyWith(
      conditions: nextConditions,
      modifiedAt: TaskItem.nextModifiedTimestamp(
        now,
        label.effectiveModifiedAt,
      ),
    );
  }

  /// Removes [deletedLocationId] from [task]'s location conditions, inserting `location any` when an assigned label in [postCascadeLabelsWithLocation] still defines a location rule per Section 6.8.1.
  static TaskItem _cascadeLocationDeletionOnTask(
    TaskItem task,
    String deletedLocationId,
    Set<String> postCascadeLabelsWithLocation,
    DateTime now,
  ) {
    if (!_referencesLocationId(task.conditions, deletedLocationId)) {
      return task;
    }
    final nextConditions = <TaskCondition>[];
    for (final rule in task.conditions) {
      if (rule is! LocationTaskCondition) {
        nextConditions.add(rule);
        continue;
      }
      final remainingIds = rule.locationIds
          .where((id) => id != deletedLocationId)
          .toList();
      if (remainingIds.isNotEmpty) {
        nextConditions.add(LocationTaskCondition.fromIds(remainingIds));
      } else if (task.labelIds.any(postCascadeLabelsWithLocation.contains)) {
        nextConditions.add(
          const GroupResetTaskCondition(targetGroup: ConditionGroup.location),
        );
      }
    }
    return task.copyWith(
      conditions: nextConditions,
      modifiedAt: TaskItem.nextModifiedTimestamp(now, task.effectiveModifiedAt),
    );
  }

  /// Trims, validates, and caps [links] at [TaskLink.maxLinksPerTask] while preserving order.
  static List<TaskLink> _cleanLinks(List<TaskLink> links) {
    final cleaned = <TaskLink>[];
    for (final link in links) {
      if (cleaned.length >= TaskLink.maxLinksPerTask) break;
      final parsed = TaskLink.tryParse(rawTitle: link.title, rawUri: link.uri);
      if (parsed != null) cleaned.add(parsed);
    }
    return cleaned;
  }

  /// Trims and filters out empty subtask entries.
  static List<SubtaskItem> _cleanSubtasks(List<SubtaskItem> subtasks) => [
    for (final step in subtasks)
      if (step.title.trim().isNotEmpty)
        SubtaskItem(title: step.title.trim(), isCompleted: step.isCompleted),
  ];

  /// Coalesces [LocationTaskCondition] rules into a single canonical rule when referencing `<location-id>` tokens.
  static List<LocationTaskCondition> _coalesceLocationConditions(
    Iterable<LocationTaskCondition> rules,
  ) {
    final ids = <String>[];
    final legacyRules = <LocationTaskCondition>[];
    for (final rule in rules) {
      if (rule.locationIds.isNotEmpty) {
        ids.addAll(rule.locationIds);
      } else {
        legacyRules.add(rule);
      }
    }
    if (ids.isEmpty) return legacyRules;
    return <LocationTaskCondition>[LocationTaskCondition.fromIds(ids)];
  }

  /// Collects all task IDs, label IDs, location IDs, and retained deletion record IDs on [board] (`TDF_SPEC_0.6.0.md` Section 2.9).
  static Set<String> _collectAllUsedEntityIds(NormalizedTierSlices board) =>
      <String>{
        for (final task in board.allTasks) task.id,
        for (final task in board.allTasks) ...task.blockedByTaskIds,
        for (final task in board.allTasks) ...task.labelIds,
        for (final label in board.labels) label.id,
        for (final location in board.locations) location.id,
        for (final record in board.deletedBlock.tasks) record.taskId,
        for (final record in board.deletedBlock.labels) record.labelId,
        for (final record in board.deletedBlock.locations) record.locationId,
      };

  /// Filters and orders task condition rules of type [T] for [group], or returns a single [GroupResetTaskCondition] when reset.
  static Iterable<TaskCondition> _groupRules<T extends TaskCondition>(
    List<TaskCondition> rules,
    ConditionGroup group,
  ) {
    if (rules.any(
      (rule) => rule is GroupResetTaskCondition && rule.targetGroup == group,
    )) {
      return <TaskCondition>[GroupResetTaskCondition(targetGroup: group)];
    }
    if (group == ConditionGroup.location) {
      return _coalesceLocationConditions(
        rules.whereType<LocationTaskCondition>(),
      );
    }
    return rules.whereType<T>();
  }

  /// Returns whether [conditions] contains a non-empty [LocationTaskCondition].
  static bool _hasLocationConditionRule(List<TaskCondition> conditions) =>
      conditions.any(
        (rule) =>
            rule is LocationTaskCondition &&
            (rule.locationIds.isNotEmpty || rule.radiusMeters > 0),
      );

  /// Applies [transform] to every task across all slices of [board].
  static NormalizedTierSlices _mapBoardTasks(
    NormalizedTierSlices board,
    TaskItem Function(TaskItem task) transform, {
    List<TdfLabel>? labels,
    List<TdfLocation>? locations,
    TdfDeletedBlock? deletedBlock,
  }) => TaskBoardEvaluator.normalizeTierSlices(
    focus: board.focus.map(transform).toList(),
    ready: board.ready.map(transform).toList(),
    planned: board.planned.map(transform).toList(),
    blocked: board.blocked.map(transform).toList(),
    someday: board.someday.map(transform).toList(),
    completed: board.completed.map(transform).toList(),
    scopedHidden: board.scopedHidden.map(transform).toList(),
    labels: labels ?? board.labels,
    locations: locations ?? board.locations,
    deletedBlock: deletedBlock ?? board.deletedBlock,
    explicitQueueBlock: board.queueBlock,
  );

  /// Returns whether any [LocationTaskCondition] in [conditions] references [locationId].
  static bool _referencesLocationId(
    List<TaskCondition> conditions,
    String locationId,
  ) => conditions.any(
    (rule) =>
        rule is LocationTaskCondition && rule.locationIds.contains(locationId),
  );

  /// Reschedules a completed recurring [task] on [board] for its next cycle per `TDF_SPEC_0.6.0.md` Sections 6.4, 6.9.3, and 6.10.3.
  static TaskItem? _reschedule(
    NormalizedTierSlices board,
    TaskItem task,
    DateTime now,
    TdfTimeZoneContext zone, [
    DateTime? preserveModifiedAt,
  ]) {
    final repeatRule = task.repeatRule;
    if (repeatRule == null) return null;
    if (task.completions >= TdfTaskDependency.maxCompletions) {
      throw const FormatException('LimitExceeded');
    }
    final nextModified =
        preserveModifiedAt ??
        TaskItem.nextModifiedTimestamp(now, task.effectiveModifiedAt);
    final rearmedDependencies = TaskBoardQueueMutator.rearmDependencies(
      board,
      task.dependencies,
    );
    final resetSubtasks = TaskBoardQueueMutator.setAllSubtasksCompleted(
      task.subtasks,
      false,
    );
    if (task.dueAt case final currentDueUtc?) {
      final scheduleNext = repeatRule.nextScheduleAnchoredOccurrence(
        completedAtUtc: now,
        oldDueUtc: currentDueUtc,
        oldSuspendedUtc: task.isSuspendedForever ? null : task.suspendedAt,
        isSuspendedForever: task.isSuspendedForever,
        timeZone: zone,
      );
      AppLogger.info(
        LogTag.domain,
        'Rescheduled recurring task id=${task.id} repeat -> nextDueUtc=${scheduleNext.newDueUtc.toIso8601String()}',
      );
      return task.copyWith(
        isCompleted: false,
        clearCompletedAt: true,
        completions: task.completions + 1,
        isPriority: true,
        suspendedAt: scheduleNext.newSuspendedUtc,
        isSuspendedForever: false,
        dueAt: scheduleNext.newDueUtc,
        repeatRule: repeatRule,
        dependencies: rearmedDependencies,
        subtasks: resetSubtasks,
        modifiedAt: nextModified,
      );
    }
    final nextDue = repeatRule.nextDueUtc(completedAtUtc: now, timeZone: zone);
    AppLogger.info(
      LogTag.domain,
      'Rescheduled recurring task id=${task.id} repeat -> nextDueUtc=${nextDue.toIso8601String()}',
    );
    return task.copyWith(
      isCompleted: false,
      clearCompletedAt: true,
      completions: task.completions + 1,
      isPriority: true,
      suspendedAt: nextDue,
      isSuspendedForever: false,
      repeatRule: repeatRule,
      dependencies: rearmedDependencies,
      subtasks: resetSubtasks,
      modifiedAt: nextModified,
    );
  }

  /// Normalizes [currentDate] (or `DateTime.now().toUtc()`) to whole UTC seconds.
  static DateTime _resolveNow(DateTime? currentDate) =>
      TaskItem.normalizeTimestamp(currentDate ?? DateTime.now().toUtc());

  /// Orders [rules] for a `label` block by group (`day`, `time`, `location`) while stripping task-only resets and coalescing location rules.
  static List<TaskCondition>? _sanitizeLabelRules(List<TaskCondition>? rules) =>
      rules == null
      ? null
      : List<TaskCondition>.unmodifiable([
          ...rules.whereType<DayTaskCondition>(),
          ...rules.whereType<TimeWindowTaskCondition>(),
          ..._coalesceLocationConditions(
            rules.whereType<LocationTaskCondition>(),
          ),
        ]);

  /// Orders [rules] for a `task` block by group (`day`, `time`, `location`) while enforcing `TDF_SPEC.md` Section 4.3 reset rules.
  static List<TaskCondition> _sanitizeTaskRules(
    List<TaskCondition>? rules,
    List<TaskCondition> fallback,
  ) {
    if (rules == null) return fallback;
    if (rules.any((rule) => rule is GlobalResetTaskCondition)) {
      return const [GlobalResetTaskCondition()];
    }
    return List<TaskCondition>.unmodifiable([
      ..._groupRules<DayTaskCondition>(rules, ConditionGroup.day),
      ..._groupRules<TimeWindowTaskCondition>(rules, ConditionGroup.time),
      ..._groupRules<LocationTaskCondition>(rules, ConditionGroup.location),
    ]);
  }

  /// Trims [value] and returns `null` when null or empty.
  static String? _trimOrNull(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isNotEmpty ? trimmed : null;
  }

  /// Resolves the effective [TdfTimeZoneContext] for [now], [localTime], and [timeZone].
  static TdfTimeZoneContext _zone(
    DateTime now,
    DateTime? localTime,
    TdfTimeZoneContext? timeZone,
  ) => TaskBoardEvaluator.resolveEffectiveTimeZone(now, localTime, timeZone);
}
