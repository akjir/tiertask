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

  /// Adds a new TDF `label` block to [board] with a unique identifier, optional `#RRGGBB` [color], and validated [links].
  static NormalizedTierSlices addLabel(
    NormalizedTierSlices board,
    String name, {
    String? color,
    String? id,
    String? note,
    bool isScoped = false,
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
    DateTime? modifiedAt,
    Iterable<TaskLink> links = const <TaskLink>[],
    List<TaskCondition> conditions = const [],
  }) {
    final validatedLinks = _validateLabelLinks(links);
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
      links: validatedLinks,
      conditions: _sanitizeLabelRules(conditions) ?? const [],
    );
    if (newLabel.canonicalDirectChildStatementCount > maxTdfStmtsPerBlock) {
      throw const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message:
            'Label block exceeds maximum of $maxTdfStmtsPerBlock statements.',
      );
    }
    final cleanupNow = _resolveNow(currentDate ?? modifiedAt);
    final cleaned = TaskBoardEvaluator.cleanupResolvedTaskBlocks(
      tasks: board.allTasks,
      deleted: board.deletedBlock,
      nowUtc: cleanupNow,
    );
    final nextLabels = <TdfLabel>[...board.labels, newLabel];
    final nextBoard =
        (cleaned.cleanedSuspendedCount > 0 || cleaned.cleanedBlockedCount > 0)
        ? TaskBoardEvaluator.reevaluateBoard(
            board,
            tasks: cleaned.tasks,
            labels: nextLabels,
            now: cleanupNow,
            localEvaluationTime: localEvaluationTime,
            timeZone: timeZone,
            dueLeadWindow: dueLeadWindow,
            pruneExpiredCompleted: false,
          )
        : board.copyWithSlices(labels: nextLabels);
    return nextBoard.logDomainMutation('addLabel id=$labelId name="$trimmed"');
  }

  /// Adds a new TDF `location` block to [board] with a unique identifier per `TDF_SPEC.md` Section 4.3 and 6.1.
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
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
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
    final cleanupNow = _resolveNow(currentDate ?? modifiedAt);
    final cleaned = TaskBoardEvaluator.cleanupResolvedTaskBlocks(
      tasks: board.allTasks,
      deleted: board.deletedBlock,
      nowUtc: cleanupNow,
    );
    final nextLocations = <TdfLocation>[...board.locations, newLocation];
    final nextBoard =
        (cleaned.cleanedSuspendedCount > 0 || cleaned.cleanedBlockedCount > 0)
        ? TaskBoardEvaluator.reevaluateBoard(
            board,
            tasks: cleaned.tasks,
            locations: nextLocations,
            now: cleanupNow,
            localEvaluationTime: localEvaluationTime,
            timeZone: timeZone,
            dueLeadWindow: dueLeadWindow,
            pruneExpiredCompleted: false,
          )
        : board.copyWithSlices(locations: nextLocations);
    return nextBoard.logDomainMutation('addLocation id=$locationId');
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

  /// Appends and canonically deduplicates a single [TaskHistoryEntry] on [taskId] (`TDF_SPEC.md` Section 4.1.2 & 6.6).
  static NormalizedTierSlices addTaskHistoryEntry(
    NormalizedTierSlices board,
    String taskId, {
    required DateTime timestampUtc,
    required String text,
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
  }) {
    final validatedEntry = _validateHistoryEntry(timestampUtc, text);
    final prior = board.findTask(taskId);
    if (prior == null) return board;
    final nextHistory = TaskHistoryEntry.normalizeList(<TaskHistoryEntry>[
      ...prior.history,
      validatedEntry,
    ]);
    if (listEquals(nextHistory, prior.history)) {
      return board;
    }
    if (nextHistory.length > maxTdfHistoryPerTask) {
      throw const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message:
            'Task exceeds maximum of $maxTdfHistoryPerTask history entries.',
      );
    }
    final now = _resolveNow(currentDate);
    final stamp = _nextMutationModifiedAt(now, prior.effectiveModifiedAt);
    final updatedTask = prior.copyWith(history: nextHistory, modifiedAt: stamp);
    _ensureTaskStatementBound(updatedTask);
    final cleaned = TaskBoardEvaluator.cleanupResolvedTaskBlocks(
      tasks: board.allTasks.map(
        (item) => item.id == taskId ? updatedTask : item,
      ),
      deleted: board.deletedBlock,
      nowUtc: now,
      alreadyStampedTaskIds: <String>{taskId},
    );
    return TaskBoardEvaluator.reevaluateBoard(
      board,
      tasks: cleaned.tasks,
      now: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
      pruneExpiredCompleted: false,
    ).logDomainMutation(
      'addTaskHistoryEntry id=$taskId historyCount=${nextHistory.length}',
    );
  }

  /// Marks an active task on [board] as done per `TDF_SPEC.md` Sections 6.4 and 6.9.4.
  static NormalizedTierSlices completeTask(
    NormalizedTierSlices board,
    String taskId, {
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
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
    final completedTask = next ?? task.toCompleted(now);
    _ensureTaskStatementBound(completedTask);
    final nextQueue = TaskBoardQueueMutator.updateQueueForEditedTask(
      board.queueBlock,
      task,
      completedTask,
      next != null,
      now,
    );
    final nextTasks = next != null
        ? board.allTasks.map((item) => item.id == taskId ? next : item)
        : <TaskItem>[
            completedTask,
            ...board.allTasks.where((item) => item.id != taskId),
          ];
    final cleaned = TaskBoardEvaluator.cleanupResolvedTaskBlocks(
      tasks: nextTasks,
      deleted: board.deletedBlock,
      nowUtc: now,
      alreadyStampedTaskIds: <String>{taskId},
    );
    final suffix = next != null ? ' (recurring)' : '';
    return TaskBoardEvaluator.reevaluateBoard(
      board,
      tasks: cleaned.tasks,
      queueBlock: nextQueue,
      now: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
    ).logDomainMutation('completeTask$suffix id=$taskId');
  }

  /// Deletes the label with [labelId] from [board], removes its reference from all tasks (applying `scoped` global-view flood protection per Section 6.8.1), and records the deletion.
  static NormalizedTierSlices deleteLabel(
    NormalizedTierSlices board,
    String labelId, {
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
  }) {
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
    final stampedTaskIds = <String>{};
    final updatedTasks = <TaskItem>[];
    for (final task in board.allTasks) {
      if (!task.labelIds.contains(labelId)) {
        updatedTasks.add(task);
        continue;
      }
      stampedTaskIds.add(task.id);
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
    final nextDeletedBlock = TaskBoardEvaluator.recordLabelDeletion(
      board.deletedBlock,
      record,
    );
    final cleaned = TaskBoardEvaluator.cleanupResolvedTaskBlocks(
      tasks: updatedTasks,
      deleted: nextDeletedBlock,
      nowUtc: now,
      alreadyStampedTaskIds: stampedTaskIds,
    );
    return TaskBoardEvaluator.reevaluateBoard(
      board,
      tasks: cleaned.tasks,
      labels: board.labels.where((item) => item.id != labelId).toList(),
      deletedBlock: nextDeletedBlock,
      queueBlock: nextQueueBlock,
      now: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
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
    Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
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
    final stampedTaskIds = <String>{};
    final updatedTasks = <TaskItem>[];
    for (final task in board.allTasks) {
      final cascaded = _cascadeLocationDeletionOnTask(
        task,
        locationId,
        postCascadeLabelsWithLocation,
        now,
      );
      if (!identical(cascaded, task)) {
        stampedTaskIds.add(task.id);
      }
      updatedTasks.add(cascaded);
    }
    final remainingLocations = board.locations
        .where((item) => item.id != locationId)
        .toList();
    final nextDeletedBlock = TaskBoardEvaluator.recordLocationDeletion(
      board.deletedBlock,
      record,
    );
    final cleaned = TaskBoardEvaluator.cleanupResolvedTaskBlocks(
      tasks: updatedTasks,
      deleted: nextDeletedBlock,
      nowUtc: now,
      alreadyStampedTaskIds: stampedTaskIds,
    );
    return TaskBoardEvaluator.reevaluateBoard(
      board,
      tasks: cleaned.tasks,
      labels: updatedLabels,
      locations: remainingLocations,
      deletedBlock: nextDeletedBlock,
      now: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
      pruneExpiredCompleted: false,
    ).logDomainMutation('deleteLocation id=$locationId');
  }

  /// Deletes the task with [taskId] from [board], removes its `queue` entry, records the deletion in `deletedBlock`, and strips `blocked` references targeting [taskId] on open dependents.
  static NormalizedTierSlices deleteTask(
    NormalizedTierSlices board,
    String taskId, {
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
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
    final nextDeletedBlock = TaskBoardEvaluator.recordTaskDeletion(
      board.deletedBlock,
      record,
    );
    final cleaned = TaskBoardEvaluator.cleanupResolvedTaskBlocks(
      tasks: board.allTasks.where((item) => item.id != taskId),
      deleted: nextDeletedBlock,
      nowUtc: now,
    );
    return TaskBoardEvaluator.reevaluateBoard(
      board,
      tasks: cleaned.tasks,
      deletedBlock: nextDeletedBlock,
      queueBlock: TaskBoardQueueMutator.removeTaskFromQueue(
        board.queueBlock,
        taskId,
        now,
      ),
      now: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
    ).logDomainMutation('deleteTask id=$taskId');
  }

  /// Removes a single [TaskHistoryEntry] from [taskId] on [board] when present (`TDF_SPEC.md` Section 4.1.2 & 6.6).
  static NormalizedTierSlices removeTaskHistoryEntry(
    NormalizedTierSlices board,
    String taskId, {
    required TaskHistoryEntry entry,
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
  }) {
    final prior = board.findTask(taskId);
    if (prior == null || !prior.history.contains(entry)) {
      return board;
    }
    final nextHistory = TaskHistoryEntry.normalizeList(<TaskHistoryEntry>[
      for (final existing in prior.history)
        if (existing != entry) existing,
    ]);
    if (listEquals(nextHistory, prior.history)) {
      return board;
    }
    final now = _resolveNow(currentDate);
    final stamp = _nextMutationModifiedAt(now, prior.effectiveModifiedAt);
    final updatedTask = prior.copyWith(history: nextHistory, modifiedAt: stamp);
    final cleaned = TaskBoardEvaluator.cleanupResolvedTaskBlocks(
      tasks: board.allTasks.map(
        (item) => item.id == taskId ? updatedTask : item,
      ),
      deleted: board.deletedBlock,
      nowUtc: now,
      alreadyStampedTaskIds: <String>{taskId},
    );
    return TaskBoardEvaluator.reevaluateBoard(
      board,
      tasks: cleaned.tasks,
      now: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
      pruneExpiredCompleted: false,
    ).logDomainMutation(
      'removeTaskHistoryEntry id=$taskId historyCount=${nextHistory.length}',
    );
  }

  /// Toggles the subtask step at [stepIndex] on [taskId] in [board], auto-completing the task when `subtasks auto-finish` is enabled.
  static NormalizedTierSlices toggleSubtask(
    NormalizedTierSlices board,
    String taskId,
    int stepIndex, {
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
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
    if (!willAutoComplete) {
      final cleaned = TaskBoardEvaluator.cleanupResolvedTaskBlocks(
        tasks: replaced.allTasks,
        deleted: replaced.deletedBlock,
        nowUtc: now,
        alreadyStampedTaskIds: <String>{taskId},
      );
      final nextBoard =
          (cleaned.cleanedSuspendedCount > 0 || cleaned.cleanedBlockedCount > 0)
          ? TaskBoardEvaluator.reevaluateBoard(
              replaced,
              tasks: cleaned.tasks,
              now: now,
              localEvaluationTime: localEvaluationTime,
              timeZone: timeZone,
              dueLeadWindow: dueLeadWindow,
              pruneExpiredCompleted: false,
            )
          : replaced;
      return nextBoard.logDomainMutation(logMessage);
    }
    return completeTask(
      replaced,
      taskId,
      currentDate: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
    ).logDomainMutation('$logMessage (auto-completed)');
  }

  /// Updates an existing label with [labelId] on [board], re-evaluates the 6-tier pipeline, and ignores empty/duplicate names or pure no-op updates.
  static NormalizedTierSlices updateLabel(
    NormalizedTierSlices board,
    String labelId, {
    String? name,
    bool? isScoped,
    String? color,
    bool clearColor = false,
    String? note,
    bool clearNote = false,
    Iterable<TaskLink>? links,
    List<TaskCondition>? conditions,
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
  }) {
    final validatedLinks = links != null ? _validateLabelLinks(links) : null;
    final prior = board.findLabel(labelId);
    if (prior == null) return board;
    final trimmedName = (name ?? prior.name).trim();
    if (trimmedName.isEmpty ||
        board.hasDuplicateLabelName(trimmedName, excludingLabelId: labelId)) {
      return board;
    }
    final normalizedColor = TdfColor.normalizeHex(color);
    final cleanNote = _trimOrNull(note);
    final candidateWithoutStamp = prior.copyWith(
      name: trimmedName,
      isScoped: isScoped,
      color: normalizedColor,
      clearColor: clearColor || (color != null && normalizedColor == null),
      note: cleanNote,
      clearNote: clearNote || (note != null && cleanNote == null),
      links: validatedLinks,
      conditions: _sanitizeLabelRules(conditions),
    );
    if (candidateWithoutStamp == prior) {
      return board;
    }
    final now = _resolveNow(currentDate);
    final stamp = TaskItem.nextModifiedTimestamp(
      now,
      prior.effectiveModifiedAt,
    );
    final updatedLabel = candidateWithoutStamp.copyWith(modifiedAt: stamp);
    if (updatedLabel.canonicalDirectChildStatementCount > maxTdfStmtsPerBlock) {
      throw const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message:
            'Label block exceeds maximum of $maxTdfStmtsPerBlock statements.',
      );
    }
    final cleaned = TaskBoardEvaluator.cleanupResolvedTaskBlocks(
      tasks: board.allTasks,
      deleted: board.deletedBlock,
      nowUtc: now,
    );
    final logMessage =
        'updateLabel/renameLabel id=$labelId name="$trimmedName"';
    return TaskBoardEvaluator.reevaluateBoard(
      board,
      tasks: cleaned.tasks,
      labels: <TdfLabel>[
        for (final item in board.labels)
          item.id == labelId ? updatedLabel : item,
      ],
      now: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
    ).logDomainMutation(logMessage);
  }

  /// Updates an existing location with [locationId] on [board] per `TDF_SPEC.md` Section 4.3 and 6.6.
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
    Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
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
    final cleanNote = _trimOrNull(note);
    final cleanSource = _trimOrNull(source);
    final candidateWithoutStamp = prior.copyWith(
      name: trimmedName,
      latitude: nextLatitude,
      longitude: nextLongitude,
      radius: nextRadius,
      note: cleanNote,
      clearNote: clearNote || (note != null && cleanNote == null),
      source: cleanSource,
      clearSource: clearSource || (source != null && cleanSource == null),
    );
    if (candidateWithoutStamp == prior) {
      return board;
    }
    final now = _resolveNow(currentDate);
    final stamp = TaskItem.nextModifiedTimestamp(
      now,
      prior.effectiveModifiedAt,
    );
    final updatedLocation = candidateWithoutStamp.copyWith(modifiedAt: stamp);
    final cleaned = TaskBoardEvaluator.cleanupResolvedTaskBlocks(
      tasks: board.allTasks,
      deleted: board.deletedBlock,
      nowUtc: now,
    );
    return TaskBoardEvaluator.reevaluateBoard(
      board,
      tasks: cleaned.tasks,
      locations: <TdfLocation>[
        for (final item in board.locations)
          item.id == locationId ? updatedLocation : item,
      ],
      now: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
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
    String? suspendedNote,
    bool clearSuspendedAt = false,
    bool clearSuspendedNote = false,
    DateTime? dueAt,
    bool? isDuePassive,
    String? dueNote,
    bool clearDueAt = false,
    bool clearDueNote = false,
    TaskRepeatRule? repeatRule,
    bool clearRepeatRule = false,
    List<String>? blockedByTaskIds,
    List<TdfTaskDependency>? dependencies,
    TaskOrigin? origin,
    bool clearOrigin = false,
    List<TaskLink>? links,
    Iterable<TaskHistoryEntry>? history,
    List<TaskCondition>? conditions,
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
    DateTime? modifiedAt,
    bool isNewTask = false,
  }) {
    final validatedSuspendedNote =
        (!clearSuspendedNote && suspendedNote != null)
        ? _validateScheduleNote(suspendedNote, 'suspendedNote')
        : null;
    final validatedDueNote = (!clearDueNote && dueNote != null)
        ? _validateScheduleNote(dueNote, 'dueNote')
        : null;
    final validatedHistory = history != null
        ? _validateHistoryEntries(history)
        : null;
    if (!clearRepeatRule && repeatRule != null) {
      _validateRepeatRule(repeatRule);
    }
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
    _validateRepeatRule(repeat);
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
    final nextSuspendedNote = (clearDefer || clearSuspendedNote)
        ? null
        : (validatedSuspendedNote ?? prior?.suspendedNote);
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
    final explicitlyPromotedPriority =
        (isPriority == true || targetTier == TaskTier.focus) && nextPriority;
    final stamp = prior != null
        ? TaskItem.nextModifiedTimestamp(now, prior.effectiveModifiedAt)
        : TaskItem.normalizeTimestamp(modifiedAt ?? now);
    final prevCount = prior?.completions ?? 0;
    final armed = isDone
        ? const <TdfTaskDependency>[]
        : _armDeps(board, taskId, blockedByTaskIds, dependencies, prior);
    final nextDueAt = (clearDueAt || (isRestoring && dueAt == null))
        ? null
        : (dueAt ?? prior?.dueAt);
    final normalizedNextDueAt = nextDueAt != null
        ? TaskItem.normalizeTimestamp(nextDueAt)
        : null;
    final normalizedPriorDueAt = switch (prior?.dueAt) {
      final priorDue? => TaskItem.normalizeTimestamp(priorDue),
      null => null,
    };
    final nextIsDuePassive = normalizedNextDueAt == null
        ? false
        : (prior != null &&
                  normalizedNextDueAt == normalizedPriorDueAt &&
                  !explicitlyPromotedPriority
              ? (isDuePassive ?? prior.isDuePassive)
              : (isDuePassive ?? false));
    final nextDueNote = (normalizedNextDueAt == null || clearDueNote)
        ? null
        : (validatedDueNote ?? prior?.dueNote);
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
      suspendedNote: nextSuspendedNote,
      dueAt: nextDueAt,
      isDuePassive: nextIsDuePassive,
      dueNote: nextDueNote,
      repeatRule: repeat,
      dependencies: isRestoring
          ? TaskBoardQueueMutator.rearmDependencies(board, armed)
          : armed,
      labelIds: labelIds ?? prior?.labelIds ?? const [],
      origin: nextOrigin,
      links: links != null ? _cleanLinks(links) : (prior?.links ?? const []),
      history: validatedHistory ?? prior?.history ?? const <TaskHistoryEntry>[],
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
    _ensureTaskStatementBound(finalTask);
    final nextQueue = TaskBoardQueueMutator.updateQueueForEditedTask(
      board.queueBlock,
      prior,
      finalTask,
      isRecurringAuto || (!isDone && !isSomeday),
      now,
    );
    if (prior != null && !isNewTask) {
      final finalWithoutStamp = finalTask.copyWith(
        modifiedAt: prior.modifiedAt,
        clearModifiedAt: prior.modifiedAt == null,
      );
      if (finalWithoutStamp == prior &&
          identical(nextQueue, board.queueBlock) &&
          (targetTier == null || board.findTierOfTask(taskId) == targetTier)) {
        return board;
      }
    }
    final added = isDone
        ? <TaskItem>[finalTask, ...board.allTasks]
        : <TaskItem>[...board.allTasks, finalTask];
    final nextTasks = prior != null
        ? board.allTasks.map((item) => item.id == taskId ? finalTask : item)
        : added;
    final cleaned = TaskBoardEvaluator.cleanupResolvedTaskBlocks(
      tasks: nextTasks,
      deleted: board.deletedBlock,
      nowUtc: now,
      alreadyStampedTaskIds: <String>{taskId},
    );
    final action = isNewTask ? 'addTask' : 'updateTask';
    return TaskBoardEvaluator.reevaluateBoard(
      board,
      tasks: cleaned.tasks,
      queueBlock: nextQueue,
      now: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
    ).logDomainMutation('$action id=$taskId title="$trimmed"');
  }

  /// Replaces [oldEntry] on [taskId] with a validated `(newTimestampUtc, newText)` history entry (`TDF_SPEC.md` Section 4.1.2 & 6.6).
  static NormalizedTierSlices updateTaskHistoryEntry(
    NormalizedTierSlices board,
    String taskId, {
    required TaskHistoryEntry oldEntry,
    required DateTime newTimestampUtc,
    required String newText,
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    Duration? dueLeadWindow = TaskBoardEvaluator.defaultDueLeadWindow,
  }) {
    final replacement = _validateHistoryEntry(newTimestampUtc, newText);
    final prior = board.findTask(taskId);
    if (prior == null || !prior.history.contains(oldEntry)) {
      return board;
    }
    final nextHistory = TaskHistoryEntry.normalizeList(<TaskHistoryEntry>[
      for (final existing in prior.history)
        existing == oldEntry ? replacement : existing,
    ]);
    if (listEquals(nextHistory, prior.history)) {
      return board;
    }
    if (nextHistory.length > maxTdfHistoryPerTask) {
      throw const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message:
            'Task exceeds maximum of $maxTdfHistoryPerTask history entries.',
      );
    }
    final now = _resolveNow(currentDate);
    final stamp = _nextMutationModifiedAt(now, prior.effectiveModifiedAt);
    final updatedTask = prior.copyWith(history: nextHistory, modifiedAt: stamp);
    _ensureTaskStatementBound(updatedTask);
    final cleaned = TaskBoardEvaluator.cleanupResolvedTaskBlocks(
      tasks: board.allTasks.map(
        (item) => item.id == taskId ? updatedTask : item,
      ),
      deleted: board.deletedBlock,
      nowUtc: now,
      alreadyStampedTaskIds: <String>{taskId},
    );
    return TaskBoardEvaluator.reevaluateBoard(
      board,
      tasks: cleaned.tasks,
      now: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
      pruneExpiredCompleted: false,
    ).logDomainMutation(
      'updateTaskHistoryEntry id=$taskId historyCount=${nextHistory.length}',
    );
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

  /// Collects all task IDs, label IDs, location IDs, and retained deletion record IDs on [board] (`TDF_SPEC.md` Section 2.9).
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

  /// Verifies that [task] does not exceed [maxTdfStmtsPerBlock] direct child statements.
  static void _ensureTaskStatementBound(TaskItem task) {
    if (task.canonicalDirectChildStatementCount > maxTdfStmtsPerBlock) {
      throw const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message:
            'Task block exceeds maximum of $maxTdfStmtsPerBlock statements.',
      );
    }
  }

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

  /// Returns whether [value] is empty or consists solely of ASCII `<note>` whitespace (`0x20`, `\t`, `\n`, `\r`).
  static bool _isAsciiNoteWhitespaceOnly(String value) {
    for (var i = 0; i < value.length; i++) {
      final unit = value.codeUnitAt(i);
      if (unit != 0x20 && unit != 0x09 && unit != 0x0A && unit != 0x0D) {
        return false;
      }
    }
    return true;
  }

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

  /// Advances `modifiedAt` once for a task mutation, throwing [TdfException] on `9999` overflow.
  static DateTime _nextMutationModifiedAt(
    DateTime now,
    DateTime previousEffectiveModifiedAt,
  ) {
    try {
      return TaskItem.nextModifiedTimestamp(now, previousEffectiveModifiedAt);
    } on FormatException {
      throw const TdfException(
        kind: TdfErrorKind.invalidTimestamp,
        line: 1,
        message: 'Task modified timestamp exceeds supported 9999-12-31 23:59:59 UTC.',
      );
    }
  }

  /// Returns whether any [LocationTaskCondition] in [conditions] references [locationId].
  static bool _referencesLocationId(
    List<TaskCondition> conditions,
    String locationId,
  ) => conditions.any(
    (rule) =>
        rule is LocationTaskCondition && rule.locationIds.contains(locationId),
  );

  /// Reschedules a completed recurring [task] on [board] for its next cycle per `TDF_SPEC.md` Sections 6.4, 6.9.3, and 6.10.3.
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
        timeZone: zone,
      );
      final shouldDefer = scheduleNext.newSuspendedUtc.isAfter(now);
      AppLogger.info(
        LogTag.domain,
        'Rescheduled recurring task id=${task.id} repeat -> nextDueUtc=${scheduleNext.newDueUtc.toIso8601String()}',
      );
      return task.copyWith(
        isCompleted: false,
        clearCompletedAt: true,
        completions: task.completions + 1,
        isPriority: true,
        suspendedAt: shouldDefer ? scheduleNext.newSuspendedUtc : null,
        clearSuspendedAt: !shouldDefer,
        clearSuspendedNote: true,
        isSuspendedForever: false,
        dueAt: scheduleNext.newDueUtc,
        isDuePassive: false,
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
      clearSuspendedNote: true,
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

  /// Validates and normalizes an iterable of [TaskHistoryEntry] items against `0.7.0` limits.
  static List<TaskHistoryEntry> _validateHistoryEntries(
    Iterable<TaskHistoryEntry> entries,
  ) {
    final validated = <TaskHistoryEntry>[];
    for (final entry in entries) {
      validated.add(_validateHistoryEntry(entry.timestampUtc, entry.text));
    }
    final normalized = TaskHistoryEntry.normalizeList(validated);
    if (normalized.length > maxTdfHistoryPerTask) {
      throw const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message:
            'Task exceeds maximum of $maxTdfHistoryPerTask history entries.',
      );
    }
    return normalized;
  }

  /// Validates a single `(timestampUtc, text)` history entry under `TDF_SPEC.md` Section 4.1.2 & Section 8.
  static TaskHistoryEntry _validateHistoryEntry(
    DateTime timestampUtc,
    String text,
  ) {
    final normalizedTs = TaskItem.normalizeTimestamp(timestampUtc);
    if (!TdfCalendar.isWithinTimestampBounds(normalizedTs)) {
      throw const TdfException(
        kind: TdfErrorKind.invalidTimestamp,
        line: 1,
        message: 'Task history timestamp is outside 0001..9999 UTC.',
      );
    }
    final validatedText = _validateSingleLineText(text, 'history text');
    return TaskHistoryEntry(timestampUtc: normalizedTs, text: validatedText);
  }

  /// Validates all [links] for a `label` block against [maxTdfLinksPerLabel], single-line `<title>`, and `<uri>` rules.
  static List<TaskLink> _validateLabelLinks(Iterable<TaskLink> links) {
    final list = List<TaskLink>.from(links);
    if (list.length > maxTdfLinksPerLabel) {
      throw const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message: 'Label exceeds maximum of $maxTdfLinksPerLabel links.',
      );
    }
    if (list.isEmpty) return const <TaskLink>[];
    final validated = <TaskLink>[];
    for (final link in list) {
      final title = _validateSingleLineText(link.title, 'link title');
      final uri = _validateStrictUri(link.uri);
      validated.add(TaskLink(title: title, uri: uri));
    }
    return List<TaskLink>.unmodifiable(validated);
  }

  /// Validates [repeat] count (`1..3650`) and `leadDays` (`0..3650`) bounds.
  static void _validateRepeatRule(TaskRepeatRule? repeat) {
    if (repeat == null) return;
    if (repeat.count < 1 || repeat.leadDays < 0) {
      throw const TdfException(
        kind: TdfErrorKind.invalidNumber,
        line: 1,
        message: 'Repeat count must be >= 1 and leadDays must be >= 0.',
      );
    }
    if (repeat.count > TaskRepeatRule.maxRepeatCount ||
        repeat.leadDays > TaskRepeatRule.maxRepeatCount) {
      throw const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message:
            'Repeat count and leadDays must not exceed ${TaskRepeatRule.maxRepeatCount}.',
      );
    }
  }

  /// Validates an optional multi-line schedule [rawNote] (`suspendedNote` or `dueNote`) under `<note>` grammar rules.
  static String _validateScheduleNote(String rawNote, String fieldName) {
    final scalarCount = TdfCalendar.countUnicodeScalars(rawNote);
    if (scalarCount == null) {
      throw TdfException(
        kind: TdfErrorKind.unexpectedToken,
        line: 1,
        message: '$fieldName contains an unpaired UTF-16 surrogate.',
      );
    }
    for (var i = 0; i < rawNote.length; i++) {
      final unit = rawNote.codeUnitAt(i);
      final isIllegalControl =
          (unit <= 0x1F && unit != 0x09 && unit != 0x0A && unit != 0x0D) ||
          unit == 0x7F;
      if (isIllegalControl) {
        throw TdfException(
          kind: TdfErrorKind.unexpectedToken,
          line: 1,
          message: '$fieldName contains an illegal control character.',
        );
      }
    }
    if (_isAsciiNoteWhitespaceOnly(rawNote)) {
      throw TdfException(
        kind: TdfErrorKind.emptyText,
        line: 1,
        message:
            '$fieldName must contain at least one non-whitespace graphic character.',
      );
    }
    if (scalarCount > maxTdfNoteLength) {
      throw TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message: '$fieldName exceeds maximum of $maxTdfNoteLength characters.',
      );
    }
    return rawNote;
  }

  /// Validates a single-line `<text>` value (`1..500` Unicode scalars, rejecting control characters before checking emptiness).
  static String _validateSingleLineText(String rawText, String fieldName) {
    final scalarCount = TdfCalendar.countUnicodeScalars(rawText);
    if (scalarCount == null) {
      throw TdfException(
        kind: TdfErrorKind.unexpectedToken,
        line: 1,
        message: '$fieldName contains an unpaired UTF-16 surrogate.',
      );
    }
    var hasGraphicChar = false;
    for (var i = 0; i < rawText.length; i++) {
      final unit = rawText.codeUnitAt(i);
      if (unit <= 0x1F || unit == 0x7F) {
        throw TdfException(
          kind: TdfErrorKind.unexpectedToken,
          line: 1,
          message: '$fieldName must be single-line without control characters.',
        );
      }
      if (unit != 0x20) {
        hasGraphicChar = true;
      }
    }
    if (!hasGraphicChar) {
      throw TdfException(
        kind: TdfErrorKind.emptyText,
        line: 1,
        message: '$fieldName must not be empty or whitespace-only.',
      );
    }
    if (scalarCount > maxTdfTextLength) {
      throw TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message: '$fieldName exceeds maximum of $maxTdfTextLength characters.',
      );
    }
    return rawText;
  }

  /// Validates [rawUri] against `<uri>` bounds, non-emptiness, and allowed URI scheme rules.
  static String _validateStrictUri(String rawUri) {
    final scalarCount = TdfCalendar.countUnicodeScalars(rawUri);
    if (scalarCount == null) {
      throw const TdfException(
        kind: TdfErrorKind.unexpectedToken,
        line: 1,
        message: 'Link URI contains an unpaired UTF-16 surrogate.',
      );
    }
    var hasNonSpace = false;
    for (var i = 0; i < rawUri.length; i++) {
      final unit = rawUri.codeUnitAt(i);
      if (unit <= 0x1F || unit == 0x7F) {
        throw const TdfException(
          kind: TdfErrorKind.invalidUri,
          line: 1,
          message: 'Link URI contains an ASCII control character.',
        );
      }
      if (unit != 0x20) {
        hasNonSpace = true;
      }
    }
    if (!hasNonSpace) {
      throw const TdfException(
        kind: TdfErrorKind.emptyText,
        line: 1,
        message: 'Link URI must not be empty or whitespace-only.',
      );
    }
    if (scalarCount > TaskLink.maxUriLength) {
      throw const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message:
            'Link URI exceeds maximum of ${TaskLink.maxUriLength} characters.',
      );
    }
    if (!TaskLink.isValidUri(rawUri)) {
      throw const TdfException(
        kind: TdfErrorKind.invalidUri,
        line: 1,
        message: 'Link URI does not have a valid permitted scheme.',
      );
    }
    return rawUri;
  }

  /// Resolves the effective [TdfTimeZoneContext] for [now], [localTime], and [timeZone].
  static TdfTimeZoneContext _zone(
    DateTime now,
    DateTime? localTime,
    TdfTimeZoneContext? timeZone,
  ) => TaskBoardEvaluator.resolveEffectiveTimeZone(now, localTime, timeZone);
}
