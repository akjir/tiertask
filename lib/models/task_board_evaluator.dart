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
import 'task_board.dart';
import 'task_board_queue_mutator.dart';
import 'task_item.dart';
import 'tdf_metadata.dart';
import 'tdf_sync_metadata.dart';
import 'tdf_timezone.dart';

/// Stateless evaluation engine for [TaskBoard] 6-tier derivation, condition inheritance,
/// dependency graph reachability, and 30-day retention pruning per `TDF_SPEC.md` Sections 4.3, 5, and 6.8.
@immutable
class TaskBoardEvaluator {
  /// Private constructor for static evaluation helpers.
  const TaskBoardEvaluator._();

  /// Evaluates the active pull cycle on [board] and unblocks any tasks whose prerequisites or deferrals cleared.
  static TaskBoard applyAutoPull(
    TaskBoard board, {
    DateTime? currentDate,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  }) => reevaluateBoard(
    board,
    now: TaskItem.normalizeTimestamp(currentDate ?? DateTime.now().toUtc()),
    localEvaluationTime: localEvaluationTime,
    timeZone: timeZone,
    pruneExpiredCompleted: false,
  );

  /// Returns whether all prerequisite completion requirements in [task] are satisfied across [taskMap].
  static bool areDependenciesSatisfied(
    TaskItem task,
    Map<String, TaskItem> taskMap,
  ) {
    for (final dependency in task.dependencies) {
      final target = taskMap[dependency.taskId];
      if (target != null &&
          target.completions < dependency.requiredCompletion) {
        return false;
      }
    }
    return true;
  }

  /// Removes expired task and label deletion records (`now - deletedAt > 2,592,000` seconds) from [board]
  /// and increments `deletedBlock.generation` once when at least one record is removed per `TDF_SPEC.md` Section 6.8.3.
  static TaskBoard cleanupExpiredDeletions(
    TaskBoard board, {
    DateTime? currentDate,
  }) {
    final now = TaskItem.normalizeTimestamp(
      currentDate ?? DateTime.now().toUtc(),
    );
    final retainedTasks = board.deletedBlock.tasks
        .where((record) => !_isTimestampExpired(record.deletedAt, now))
        .toList();
    final retainedLabels = board.deletedBlock.labels
        .where((record) => !_isTimestampExpired(record.deletedAt, now))
        .toList();
    final removedCount =
        (board.deletedBlock.tasks.length - retainedTasks.length) +
        (board.deletedBlock.labels.length - retainedLabels.length);
    if (removedCount == 0) return board;
    if (board.deletedBlock.generation >= TdfDeletedBlock.maxGeneration) {
      throw const FormatException('LimitExceeded');
    }
    final nextDeletedBlock = TdfDeletedBlock(
      generation: board.deletedBlock.generation + 1,
      tasks: retainedTasks,
      labels: retainedLabels,
    );
    AppLogger.info(
      LogTag.domain,
      'cleanupExpiredDeletions removed=$removedCount generation=${nextDeletedBlock.generation}',
    );
    return board.copyWith(deletedBlock: nextDeletedBlock);
  }

  /// Derives the 6 operational tiers from [tasks] in a single $O(N)$ pass per `TDF_SPEC.md` Section 5.
  static TaskBoard evaluate({
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
        : resolveLocalEvaluationTime(evaluationTime, localEvaluationTime);
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
    final resolvedQueueBlock = queueBlock ?? TdfQueueBlock.empty;
    final queuedTaskIds = resolvedQueueBlock.taskIds.toSet();

    for (var i = 0; i < taskList.length; i++) {
      _classifyTaskIntoPipeline(
        task: taskList[i],
        nowUtc: now,
        localNow: localNow,
        taskMap: taskMap,
        labelMap: labelMap,
        queuedTaskIds: queuedTaskIds,
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

    final resolvedDeletedBlock = prunedTaskRecords.fold(
      deletedBlock ?? TdfDeletedBlock.empty,
      recordTaskDeletion,
    );
    final orderedEligible = _orderEligibleByQueue(
      eligibleById,
      resolvedQueueBlock.taskIds,
    );
    const readyEnd = TaskBoard.focusSoftLimit + TaskBoard.readySoftLimit;

    return TaskBoard(
      focus: orderedEligible.take(TaskBoard.focusSoftLimit).toList(),
      ready: orderedEligible
          .skip(TaskBoard.focusSoftLimit)
          .take(TaskBoard.readySoftLimit)
          .toList(),
      planned: orderedEligible.skip(readyEnd).toList(),
      blocked: blockedList,
      someday: somedayList,
      completed: completedList,
      labels: labels,
      deletedBlock: resolvedDeletedBlock,
      queueBlock: resolvedQueueBlock,
    );
  }

  /// Derives a filtered [TaskBoard] from [board] considering only tasks matching [activeLabelId] and GPS coordinates.
  static TaskBoard evaluateForContext(
    TaskBoard board, {
    String? activeLabelId,
    double? currentLatitude,
    double? currentLongitude,
    DateTime? evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  }) =>
      evaluate(
        tasks: board.allTasks,
        evaluationTime: evaluationTime,
        localEvaluationTime: localEvaluationTime,
        timeZone: timeZone,
        labels: board.labels,
        deletedBlock: board.deletedBlock,
        queueBlock: board.queueBlock,
        activeLabelId: activeLabelId,
        currentLatitude: currentLatitude,
        currentLongitude: currentLongitude,
      ).logDomainMutation(
        'evaluateForContext activeLabel=${activeLabelId ?? "all"}',
      );

  /// Returns whether [targetTaskId] is reachable from [startTaskId] via `blockedByTaskIds` edges in [taskMap].
  static bool isReachableInDependencyGraph({
    required String startTaskId,
    required String targetTaskId,
    required Map<String, TaskItem> taskMap,
  }) {
    final visited = <String>{};
    final frontier = <String>[startTaskId];
    var cursor = 0;
    while (cursor < frontier.length) {
      final currentId = frontier[cursor++];
      if (currentId == targetTaskId) return true;
      if (!visited.add(currentId)) continue;
      if (taskMap[currentId] case final currentTask?) {
        frontier.addAll(currentTask.blockedByTaskIds);
      }
    }
    return false;
  }

  /// Normalizes all 6 tier slices so their TDF directives match their tier placement.
  static NormalizedTierSlices normalizeTierSlices({
    required List<TaskItem> focus,
    required List<TaskItem> ready,
    required List<TaskItem> planned,
    required List<TaskItem> blocked,
    required List<TaskItem> someday,
    required List<TaskItem> completed,
    required List<TdfLabel> labels,
    required TdfQueueBlock? explicitQueueBlock,
  }) {
    final nextFocus = _normalizeOpenSlice(focus);
    final nextReady = _normalizeOpenSlice(ready);
    final nextPlanned = _normalizeOpenSlice(planned);
    final labelIdsWithConditions = <String>{
      for (final label in labels)
        if (label.conditions.isNotEmpty) label.id,
    };
    final nextBlocked = <TaskItem>[
      for (final task in blocked)
        task.copyWith(
          isCompleted: false,
          clearCompletedAt: true,
          isSuspendedForever:
              task.isSuspendedForever ||
              (explicitQueueBlock == null &&
                  task.blockedByTaskIds.isEmpty &&
                  task.conditions.isEmpty &&
                  !task.labelIds.any(labelIdsWithConditions.contains) &&
                  task.suspendedAt == null),
        ),
    ];
    final nextSomeday = <TaskItem>[
      for (final task in someday)
        task.copyWith(
          isCompleted: false,
          clearCompletedAt: true,
          isPriority: explicitQueueBlock != null ? task.isPriority : false,
        ),
    ];
    return (
      focus: nextFocus,
      ready: nextReady,
      planned: nextPlanned,
      blocked: nextBlocked,
      someday: nextSomeday,
      completed: completed
          .map((task) => task.copyWith(isCompleted: true))
          .toList(),
      openTaskCountsByLabel: _countOpenLabels([
        ...nextFocus,
        ...nextReady,
        ...nextPlanned,
        ...nextBlocked,
        ...nextSomeday,
      ]),
      queueBlock:
          explicitQueueBlock ??
          TaskBoardQueueMutator.deriveSliceQueueBlock(
            focus: nextFocus,
            ready: nextReady,
            planned: nextPlanned,
            blocked: nextBlocked,
          ),
    );
  }

  /// Prunes tasks in Tier 6 (`Completed`) on [board] older than 30 days (`2,592,000` seconds UTC).
  static TaskBoard pruneCompletedTasks(
    TaskBoard board, {
    DateTime? currentDate,
  }) {
    final now = TaskItem.normalizeTimestamp(
      currentDate ?? DateTime.now().toUtc(),
    );
    final retained = <TaskItem>[];
    final prunedRecords = <TdfDeletedTaskRecord>[];
    for (final task in board.completed) {
      if (_isWithinRetention(task, now)) {
        retained.add(task);
      } else {
        prunedRecords.add(_toPrunedRecord(task, now));
      }
    }
    if (prunedRecords.isEmpty) return board;
    AppLogger.info(
      LogTag.domain,
      'pruneCompletedTasks pruned=${prunedRecords.length} expired tasks (>30 days)',
    );
    final nextDeleted = prunedRecords.fold(
      board.deletedBlock,
      recordTaskDeletion,
    );
    return board.copyWith(completed: retained, deletedBlock: nextDeleted);
  }

  /// Records a label deletion [record] in [current] while enforcing [TdfDeletedBlock.maxDeletedRecords].
  static TdfDeletedBlock recordLabelDeletion(
    TdfDeletedBlock current,
    TdfDeletedLabelRecord record,
  ) {
    final candidate = current.copyWith(labels: [...current.labels, record]);
    if (candidate.totalRecords > TdfDeletedBlock.maxDeletedRecords) {
      throw const FormatException('LimitExceeded');
    }
    return candidate;
  }

  /// Records a task deletion [record] in [current] while enforcing [TdfDeletedBlock.maxDeletedRecords].
  static TdfDeletedBlock recordTaskDeletion(
    TdfDeletedBlock current,
    TdfDeletedTaskRecord record,
  ) {
    final candidate = current.copyWith(tasks: [...current.tasks, record]);
    if (candidate.totalRecords > TdfDeletedBlock.maxDeletedRecords) {
      throw const FormatException('LimitExceeded');
    }
    return candidate;
  }

  /// Re-evaluates [board] with optional [tasks], [labels], [deletedBlock], and [queueBlock] overrides.
  static TaskBoard reevaluateBoard(
    TaskBoard board, {
    Iterable<TaskItem>? tasks,
    List<TdfLabel>? labels,
    TdfDeletedBlock? deletedBlock,
    TdfQueueBlock? queueBlock,
    required DateTime now,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    bool pruneExpiredCompleted = true,
  }) => evaluate(
    tasks: tasks ?? board.allTasks,
    evaluationTime: now,
    localEvaluationTime: resolveLocalEvaluationTime(now, localEvaluationTime),
    timeZone: timeZone,
    labels: labels ?? board.labels,
    deletedBlock: deletedBlock ?? board.deletedBlock,
    queueBlock: queueBlock ?? board.queueBlock,
    pruneExpiredCompleted: pruneExpiredCompleted,
  );

  /// Resolves the effective [TdfTimeZoneContext] from [timeZone] or [localEvaluationTime].
  static TdfTimeZoneContext resolveEffectiveTimeZone(
    DateTime now,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
  ) {
    if (timeZone != null) return timeZone;
    if (localEvaluationTime != null) {
      final localWall = resolveLocalEvaluationTime(now, localEvaluationTime);
      return TdfTimeZoneContext.fixedOffset(localWall.difference(now));
    }
    return TdfTimeZoneContext.utc;
  }

  /// Resolves the effective local wall-clock evaluation timestamp for `condition day` and `condition time`.
  static DateTime resolveLocalEvaluationTime(
    DateTime? evaluationTime,
    DateTime? localEvaluationTime,
  ) {
    final source = localEvaluationTime ?? evaluationTime ?? DateTime.now();
    return DateTime.utc(
      source.year,
      source.month,
      source.day,
      source.hour,
      source.minute,
      source.second,
    );
  }

  /// Returns an unmodifiable copy of [labels] sorted alphabetically by display name.
  static List<TdfLabel> sortLabelsAlphabetically(List<TdfLabel> labels) {
    if (labels.isEmpty) return const [];
    final sorted = List<TdfLabel>.from(labels)
      ..sort(_compareLabelsAlphabetically);
    return List<TdfLabel>.unmodifiable(sorted);
  }

  /// Returns whether adding [candidateBlockerId] as a prerequisite of [taskId] on [board] creates a cycle.
  static bool wouldCreateDependencyCycle(
    TaskBoard board,
    String taskId,
    String candidateBlockerId,
  ) {
    final trimmedTaskId = taskId.trim();
    final trimmedBlockerId = candidateBlockerId.trim();
    if (trimmedTaskId.isEmpty || trimmedBlockerId.isEmpty) return false;
    if (trimmedTaskId == trimmedBlockerId) return true;
    return isReachableInDependencyGraph(
      startTaskId: trimmedBlockerId,
      targetTaskId: trimmedTaskId,
      taskMap: {for (final task in board.allTasks) task.id: task},
    );
  }

  /// Evaluates whether [task]'s effective condition groups are satisfied per `TDF_SPEC.md` Section 4.3.
  static bool _areTaskConditionsSatisfied(
    TaskItem task,
    Map<String, TdfLabel> labelMap,
    DateTime evaluationTime,
    String? activeLabelId,
    double? latitude,
    double? longitude,
  ) {
    if (task.conditions.any((rule) => rule is GlobalResetTaskCondition)) {
      return true;
    }
    if (task.labelIds.isEmpty || activeLabelId != null) {
      final baseRules = activeLabelId != null
          ? (labelMap[activeLabelId]?.conditions ?? const <TaskCondition>[])
          : const <TaskCondition>[];
      return _evaluateRuleContext(
        baseRules,
        task.conditions,
        evaluationTime,
        latitude,
        longitude,
      );
    }
    for (final labelId in task.labelIds) {
      if (_evaluateRuleContext(
        labelMap[labelId]?.conditions ?? const [],
        task.conditions,
        evaluationTime,
        latitude,
        longitude,
      )) {
        return true;
      }
    }
    return false;
  }

  /// Classifies a single [task] into the Section 5 evaluation buckets.
  static void _classifyTaskIntoPipeline({
    required TaskItem task,
    required DateTime nowUtc,
    required DateTime localNow,
    required Map<String, TaskItem> taskMap,
    required Map<String, TdfLabel> labelMap,
    required Set<String> queuedTaskIds,
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
        prunedTaskRecords.add(_toPrunedRecord(task, nowUtc));
        return;
      }
      if (activeLabelId == null || task.labelIds.contains(activeLabelId)) {
        completedList.add(task.copyWith(isCompleted: true));
      }
      return;
    }
    if (activeLabelId != null && !task.labelIds.contains(activeLabelId)) return;
    if (!queuedTaskIds.contains(task.id)) {
      (_hasActiveDeferral(task, nowUtc) ? blockedList : somedayList).add(task);
      return;
    }
    if (_hasActiveDeferral(task, nowUtc) ||
        !areDependenciesSatisfied(task, taskMap) ||
        !_areTaskConditionsSatisfied(
          task,
          labelMap,
          localNow,
          activeLabelId,
          currentLatitude,
          currentLongitude,
        )) {
      blockedList.add(task);
      return;
    }
    eligibleById[task.id] = task;
  }

  /// Compares two [TdfLabel] instances alphabetically (case-insensitive, then exact, then by ID).
  static int _compareLabelsAlphabetically(TdfLabel first, TdfLabel second) {
    final lowerCompare = first.name.toLowerCase().compareTo(
      second.name.toLowerCase(),
    );
    if (lowerCompare != 0) return lowerCompare;
    final exactCompare = first.name.compareTo(second.name);
    return exactCompare != 0 ? exactCompare : first.id.compareTo(second.id);
  }

  /// Counts open tasks per label across [tasks].
  static Map<String, int> _countOpenLabels(List<TaskItem> tasks) {
    final counts = <String, int>{};
    for (final task in tasks) {
      for (final labelId in task.labelIds) {
        counts[labelId] = (counts[labelId] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// Evaluates all rules belonging to [group] within [rules] using intra-group `OR` short-circuiting.
  static bool _evaluateGroupRules(
    List<TaskCondition> rules,
    ConditionGroup group,
    DateTime evaluationTime,
    double? latitude,
    double? longitude,
  ) {
    var hasRuleInGroup = false;
    for (final rule in rules) {
      if (rule.group != group) continue;
      if (rule is GroupResetTaskCondition) return true;
      hasRuleInGroup = true;
      if (rule.isSatisfiedAt(
        evaluationTime,
        currentLatitude: latitude,
        currentLongitude: longitude,
      )) {
        return true;
      }
    }
    return !hasRuleInGroup;
  }

  /// Evaluates a single effective condition context (`day` AND `time` AND `location`) per Section 4.3.3.
  static bool _evaluateRuleContext(
    List<TaskCondition> baseRules,
    List<TaskCondition> taskRules,
    DateTime evaluationTime,
    double? latitude,
    double? longitude,
  ) {
    for (final group in ConditionGroup.values) {
      final source = taskRules.any((rule) => rule.group == group)
          ? taskRules
          : baseRules;
      if (!_evaluateGroupRules(
        source,
        group,
        evaluationTime,
        latitude,
        longitude,
      )) {
        return false;
      }
    }
    return true;
  }

  /// Checks whether [task] has an active deferral (`suspended forever` or `suspendedAt > nowUtc`).
  static bool _hasActiveDeferral(TaskItem task, DateTime nowUtc) {
    if (task.isSuspendedForever) return true;
    final suspendedUntil = task.suspendedAt;
    return suspendedUntil != null && suspendedUntil.isAfter(nowUtc);
  }

  /// Returns whether [timestamp] is strictly older than 30 days (`2,592,000` seconds) relative to [nowUtc].
  static bool _isTimestampExpired(DateTime timestamp, DateTime nowUtc) =>
      nowUtc.difference(timestamp.toUtc()).inSeconds >
      TaskBoard.completedRetentionSeconds;

  /// Returns whether [task] is within the 30-day (`2,592,000` seconds) retention window relative to [nowUtc].
  static bool _isWithinRetention(TaskItem task, DateTime nowUtc) {
    final completedDate = task.completedAt;
    return completedDate == null || !_isTimestampExpired(completedDate, nowUtc);
  }

  /// Normalizes open tasks in [slice] so `isCompleted` and `completedAt` are cleared.
  static List<TaskItem> _normalizeOpenSlice(List<TaskItem> slice) => [
    for (final task in slice)
      (task.isCompleted || task.completedAt != null)
          ? task.copyWith(isCompleted: false, clearCompletedAt: true)
          : task,
  ];

  /// Orders eligible tasks by traversing [queueTaskIds] in saved order and grouping `priority` before regular per `TDF_SPEC.md` Section 5.5.
  static List<TaskItem> _orderEligibleByQueue(
    Map<String, TaskItem> eligibleById,
    List<String> queueTaskIds,
  ) {
    if (eligibleById.isEmpty) return const <TaskItem>[];
    final priorityGroup = <TaskItem>[];
    final regularGroup = <TaskItem>[];
    final visited = <String>{};

    for (final taskId in queueTaskIds) {
      final task = eligibleById[taskId];
      if (task != null && visited.add(taskId)) {
        (task.isPriority ? priorityGroup : regularGroup).add(task);
      }
    }
    for (final task in eligibleById.values) {
      if (visited.add(task.id)) {
        (task.isPriority ? priorityGroup : regularGroup).add(task);
      }
    }
    return <TaskItem>[...priorityGroup, ...regularGroup];
  }

  /// Creates a [TdfDeletedTaskRecord] for a completed [task] pruned at [now].
  static TdfDeletedTaskRecord _toPrunedRecord(TaskItem task, DateTime now) =>
      TdfDeletedTaskRecord(
        taskId: task.id,
        deletedAt: TaskItem.nextModifiedTimestamp(
          now,
          task.effectiveModifiedAt,
        ),
        completionsCheckpoint: task.completions,
      );
}
