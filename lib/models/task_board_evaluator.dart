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
import 'tdf_location.dart';
import 'tdf_metadata.dart';
import 'tdf_sync_metadata.dart';
import 'tdf_timezone.dart';

/// Normalized task lists, label/location metadata, and sync blocks for board state evaluation and mutation.
typedef NormalizedTierSlices = ({
  List<TaskItem> focus,
  List<TaskItem> ready,
  List<TaskItem> planned,
  List<TaskItem> blocked,
  List<TaskItem> someday,
  List<TaskItem> completed,
  List<TaskItem> scopedHidden,
  List<TdfLabel> labels,
  List<TdfLocation> locations,
  TdfDeletedBlock deletedBlock,
  Map<String, int> openTaskCountsByLabel,
  Map<String, int> openTaskCountsByLocation,
  TdfQueueBlock queueBlock,
});

/// Core task collection, copy, and diagnostic logging helpers on [NormalizedTierSlices].
extension TaskBoardSlicesX on NormalizedTierSlices {
  /// Returns all tasks across all 6 tiers (plus any global-view-restricted `scoped` tasks) in canonical document order.
  List<TaskItem> get allTasks => List<TaskItem>.unmodifiable([
    ...focus,
    ...ready,
    ...planned,
    ...blocked,
    ...someday,
    ...completed,
    ...scopedHidden,
  ]);

  /// Returns a normalized copy of these slices with [completed], [labels], [locations], or [deletedBlock] replaced.
  NormalizedTierSlices copyWithSlices({
    List<TaskItem>? completed,
    List<TdfLabel>? labels,
    List<TdfLocation>? locations,
    TdfDeletedBlock? deletedBlock,
  }) => TaskBoardEvaluator.normalizeTierSlices(
    focus: focus,
    ready: ready,
    planned: planned,
    blocked: blocked,
    someday: someday,
    completed: completed ?? this.completed,
    scopedHidden: scopedHidden,
    labels: labels ?? this.labels,
    locations: locations ?? this.locations,
    deletedBlock: deletedBlock ?? this.deletedBlock,
    explicitQueueBlock: queueBlock,
  );

  /// Logs [action] with the resulting 6-tier task distribution under [LogTag.domain] and returns `this`.
  NormalizedTierSlices logDomainMutation(String action) {
    final normalized = TaskBoardEvaluator.formatDomainMutationMessage(
      action,
      focus: focus.length,
      ready: ready.length,
      planned: planned.length,
      blocked: blocked.length,
      someday: someday.length,
      completed: completed.length,
    );
    AppLogger.info(LogTag.domain, normalized);
    return this;
  }
}

/// Stateless evaluation engine for 6-tier derivation, condition inheritance,
/// dependency graph reachability, and 30-day retention pruning per `TDF_SPEC.md` Sections 4.3, 5, and 6.8.
@immutable
class TaskBoardEvaluator {
  /// Private constructor for static evaluation helpers.
  const TaskBoardEvaluator._();

  /// Retention period in days for completed tasks in Tier 6 (`Completed`) and deletion records.
  static const int completedRetentionDays = 30;

  /// Retention period in seconds (`30 * 86,400 = 2,592,000` seconds) per `TDF_SPEC.md` Section 6.8.
  static const int completedRetentionSeconds = 2592000;

  /// Soft WIP limit for Tier 1 (`Focus`).
  static const int focusSoftLimit = 3;

  /// Soft WIP limit for Tier 2 (`Ready`).
  static const int readySoftLimit = 5;

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

  /// Removes expired task, label, and location deletion records (`now - deletedAt > 2,592,000` seconds) from [board],
  /// strips `blocked` prerequisite references targeting expired task tombstones from live tasks,
  /// and increments `deletedBlock.generation` once when at least one record is removed per `TDF_SPEC_0.6.0.md` Section 6.8.3.
  static NormalizedTierSlices cleanupExpiredDeletions(
    NormalizedTierSlices board, {
    DateTime? currentDate,
  }) {
    final now = TaskItem.normalizeTimestamp(
      currentDate ?? DateTime.now().toUtc(),
    );
    final retainedTasks = <TdfDeletedTaskRecord>[];
    final expiredTaskIds = <String>{};
    for (final record in board.deletedBlock.tasks) {
      if (_isTimestampExpired(record.deletedAt, now)) {
        expiredTaskIds.add(record.taskId);
      } else {
        retainedTasks.add(record);
      }
    }
    final retainedLabels = board.deletedBlock.labels
        .where((record) => !_isTimestampExpired(record.deletedAt, now))
        .toList();
    final retainedLocations = board.deletedBlock.locations
        .where((record) => !_isTimestampExpired(record.deletedAt, now))
        .toList();
    final removedCount =
        (board.deletedBlock.tasks.length - retainedTasks.length) +
        (board.deletedBlock.labels.length - retainedLabels.length) +
        (board.deletedBlock.locations.length - retainedLocations.length);
    if (removedCount == 0) return board;
    if (board.deletedBlock.generation >= TdfDeletedBlock.maxGeneration) {
      throw const FormatException('LimitExceeded');
    }
    final nextDeletedBlock = TdfDeletedBlock(
      generation: board.deletedBlock.generation + 1,
      tasks: retainedTasks,
      labels: retainedLabels,
      locations: retainedLocations,
    );
    AppLogger.event(
      LogLevel.info,
      LogTag.domain,
      'eval.prune',
      fields: <String, Object?>{
        'kind': 'deletions',
        'removed': removedCount,
        'generation': nextDeletedBlock.generation,
      },
    );
    if (expiredTaskIds.isEmpty) {
      return board.copyWithSlices(deletedBlock: nextDeletedBlock);
    }
    var anyTaskUpdated = false;
    final updatedTasks = <TaskItem>[];
    for (final task in board.allTasks) {
      final stripped = _stripExpiredTaskDependencies(task, expiredTaskIds, now);
      if (!identical(stripped, task)) anyTaskUpdated = true;
      updatedTasks.add(stripped);
    }
    if (!anyTaskUpdated) {
      return board.copyWithSlices(deletedBlock: nextDeletedBlock);
    }
    return reevaluateBoard(
      board,
      tasks: updatedTasks,
      deletedBlock: nextDeletedBlock,
      now: now,
      pruneExpiredCompleted: false,
    );
  }

  /// Derives the 6 operational tiers from [tasks] in a single $O(N)$ pass per `TDF_SPEC_0.6.0.md` Section 5.
  static NormalizedTierSlices evaluate({
    required Iterable<TaskItem> tasks,
    DateTime? evaluationTime,
    DateTime? localEvaluationTime,
    TdfTimeZoneContext? timeZone,
    List<TdfLabel> labels = const [],
    List<TdfLocation> locations = const [],
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
    final locationMap = <String, TdfLocation>{
      for (final location in locations) location.id: location,
    };

    final completedList = <TaskItem>[];
    final somedayList = <TaskItem>[];
    final blockedList = <TaskItem>[];
    final scopedHiddenList = <TaskItem>[];
    final eligibleById = <String, TaskItem>{};
    final prunedTaskRecords = <TdfDeletedTaskRecord>[];
    final resolvedQueueBlock = queueBlock ?? TdfQueueBlock.empty;
    final queuedTaskIds = resolvedQueueBlock.taskIds.toSet();
    final hasActiveLabelFilter =
        activeLabelId != null && activeLabelId.isNotEmpty;

    for (final task in taskList) {
      final isDone = task.completedAt != null || task.isCompleted;
      if (isDone && pruneExpiredCompleted && !_isWithinRetention(task, now)) {
        prunedTaskRecords.add(_toPrunedRecord(task, now));
        continue;
      }
      if (hasActiveLabelFilter) {
        if (!task.labelIds.contains(activeLabelId)) continue;
      } else if (isRestrictedFromGlobalView(task, labelMap)) {
        scopedHiddenList.add(
          isDone
              ? task.copyWith(isCompleted: true)
              : task.copyWith(isCompleted: false, clearCompletedAt: true),
        );
        continue;
      }
      if (isDone) {
        completedList.add(task.copyWith(isCompleted: true));
        continue;
      }
      if (!queuedTaskIds.contains(task.id)) {
        (_hasActiveDeferral(task, now) ? blockedList : somedayList).add(task);
        continue;
      }
      final isBlocked =
          _hasActiveDeferral(task, now) ||
          !areDependenciesSatisfied(task, taskMap) ||
          !_areTaskConditionsSatisfied(
            task,
            labelMap,
            locationMap,
            localNow,
            hasActiveLabelFilter ? activeLabelId : null,
            currentLatitude,
            currentLongitude,
          );
      if (isBlocked) {
        blockedList.add(task);
      } else {
        eligibleById[task.id] = task;
      }
    }

    final resolvedDeletedBlock = prunedTaskRecords.fold(
      deletedBlock ?? TdfDeletedBlock.empty,
      recordTaskDeletion,
    );
    final orderedEligible = _orderEligibleByQueue(
      eligibleById,
      resolvedQueueBlock.taskIds,
    );
    const readyEnd = focusSoftLimit + readySoftLimit;

    final normalized = normalizeTierSlices(
      focus: orderedEligible.take(focusSoftLimit).toList(),
      ready: orderedEligible.skip(focusSoftLimit).take(readySoftLimit).toList(),
      planned: orderedEligible.skip(readyEnd).toList(),
      blocked: blockedList,
      someday: somedayList,
      completed: completedList,
      scopedHidden: scopedHiddenList,
      labels: labels,
      locations: locations,
      deletedBlock: resolvedDeletedBlock,
      explicitQueueBlock: resolvedQueueBlock,
    );
    if (AppLogger.shouldLog(LogLevel.debug)) {
      _logDebugEvaluation(
        normalized,
        nowUtc: now,
        taskMap: taskMap,
        activeLabelId: activeLabelId,
        currentLatitude: currentLatitude,
        currentLongitude: currentLongitude,
      );
    }
    return normalized;
  }

  /// Formats a raw domain [action] into a canonical `<event> | <key=value ...>` message.
  static String formatDomainMutationMessage(
    String action, {
    required int focus,
    required int ready,
    required int planned,
    required int blocked,
    required int someday,
    required int completed,
  }) {
    final trimmed = action.trim();
    final spaceIndex = trimmed.indexOf(' ');
    final rawVerb = spaceIndex >= 0
        ? trimmed.substring(0, spaceIndex)
        : trimmed;
    final details = spaceIndex >= 0
        ? trimmed.substring(spaceIndex + 1).trim()
        : '';
    final eventName = _mapDomainVerb(rawVerb);
    final tiersSuffix =
        'focus=$focus ready=$ready planned=$planned '
        'blocked=$blocked someday=$someday completed=$completed';
    if (details.isEmpty) {
      return '$eventName | $tiersSuffix';
    }
    return '$eventName | $details $tiersSuffix';
  }

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

  /// Returns whether [task] is restricted from the global view (`L(T) != empty` and all declared labels in `L(T)` are `scoped`) per `TDF_SPEC_0.6.0.md` Section 5.1.
  static bool isRestrictedFromGlobalView(
    TaskItem task,
    Map<String, TdfLabel> labelMap,
  ) {
    if (task.labelIds.isEmpty) return false;
    var hasDeclaredLabel = false;
    for (final labelId in task.labelIds) {
      final label = labelMap[labelId];
      if (label == null) continue;
      hasDeclaredLabel = true;
      if (!label.isScoped) return false;
    }
    return hasDeclaredLabel;
  }

  /// Normalizes all 6 tier slices so their TDF directives match their tier placement.
  static NormalizedTierSlices normalizeTierSlices({
    required List<TaskItem> focus,
    required List<TaskItem> ready,
    required List<TaskItem> planned,
    required List<TaskItem> blocked,
    required List<TaskItem> someday,
    required List<TaskItem> completed,
    List<TaskItem> scopedHidden = const [],
    required List<TdfLabel> labels,
    List<TdfLocation> locations = const [],
    required TdfDeletedBlock deletedBlock,
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
    final openTasks = <TaskItem>[
      ...nextFocus,
      ...nextReady,
      ...nextPlanned,
      ...nextBlocked,
      ...nextSomeday,
      for (final task in scopedHidden)
        if (!task.isCompleted && task.completedAt == null) task,
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
      scopedHidden: scopedHidden,
      labels: labels,
      locations: locations,
      deletedBlock: deletedBlock,
      openTaskCountsByLabel: _countOpenLabels(openTasks),
      openTaskCountsByLocation: _countOpenLocations(openTasks, labels),
      queueBlock:
          explicitQueueBlock ??
          _deriveSliceQueueBlock(
            nextFocus,
            nextReady,
            nextPlanned,
            nextBlocked,
          ),
    );
  }

  /// Prunes tasks in Tier 6 (`Completed`) on [board] older than 30 days (`2,592,000` seconds UTC).
  static NormalizedTierSlices pruneCompletedTasks(
    NormalizedTierSlices board, {
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
    AppLogger.event(
      LogLevel.info,
      LogTag.domain,
      'eval.prune',
      fields: <String, Object?>{
        'kind': 'completed',
        'pruned': prunedRecords.length,
      },
    );
    final nextDeleted = prunedRecords.fold(
      board.deletedBlock,
      recordTaskDeletion,
    );
    return board.copyWithSlices(completed: retained, deletedBlock: nextDeleted);
  }

  /// Records a label deletion [record] in [current] while enforcing [TdfDeletedBlock.maxDeletedRecords].
  static TdfDeletedBlock recordLabelDeletion(
    TdfDeletedBlock current,
    TdfDeletedLabelRecord record,
  ) {
    if (current.totalRecords >= TdfDeletedBlock.maxDeletedRecords) {
      throw const FormatException('LimitExceeded');
    }
    return current.copyWith(labels: [...current.labels, record]);
  }

  /// Records a location deletion [record] in [current] while enforcing [TdfDeletedBlock.maxDeletedRecords].
  static TdfDeletedBlock recordLocationDeletion(
    TdfDeletedBlock current,
    TdfDeletedLocationRecord record,
  ) {
    if (current.totalRecords >= TdfDeletedBlock.maxDeletedRecords) {
      throw const FormatException('LimitExceeded');
    }
    return current.copyWith(locations: [...current.locations, record]);
  }

  /// Records a task deletion [record] in [current] while enforcing [TdfDeletedBlock.maxDeletedRecords].
  static TdfDeletedBlock recordTaskDeletion(
    TdfDeletedBlock current,
    TdfDeletedTaskRecord record,
  ) {
    if (current.totalRecords >= TdfDeletedBlock.maxDeletedRecords) {
      throw const FormatException('LimitExceeded');
    }
    return current.copyWith(tasks: [...current.tasks, record]);
  }

  /// Re-evaluates [board] with optional [tasks], [labels], [locations], [deletedBlock], and [queueBlock] overrides.
  static NormalizedTierSlices reevaluateBoard(
    NormalizedTierSlices board, {
    Iterable<TaskItem>? tasks,
    List<TdfLabel>? labels,
    List<TdfLocation>? locations,
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
    locations: locations ?? board.locations,
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

  /// Returns an unmodifiable copy of [locations] sorted alphabetically by display name.
  static List<TdfLocation> sortLocationsAlphabetically(
    List<TdfLocation> locations,
  ) {
    if (locations.isEmpty) return const [];
    final sorted = List<TdfLocation>.from(locations)
      ..sort(_compareLocationsAlphabetically);
    return List<TdfLocation>.unmodifiable(sorted);
  }

  /// Returns whether adding [candidateBlockerId] as a prerequisite of [taskId] on [board] creates a cycle.
  static bool wouldCreateDependencyCycle(
    NormalizedTierSlices board,
    String taskId,
    String candidateBlockerId,
  ) {
    final startId = candidateBlockerId.trim();
    final targetId = taskId.trim();
    if (targetId.isEmpty || startId.isEmpty) return false;
    return targetId == startId ||
        isReachableInDependencyGraph(
          startTaskId: startId,
          targetTaskId: targetId,
          taskMap: {for (final task in board.allTasks) task.id: task},
        );
  }

  /// Evaluates whether [task]'s effective condition groups are satisfied per `TDF_SPEC_0.6.0.md` Section 4.4.3.
  static bool _areTaskConditionsSatisfied(
    TaskItem task,
    Map<String, TdfLabel> labelMap,
    Map<String, TdfLocation> locationMap,
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
        locationMap,
        evaluationTime,
        latitude,
        longitude,
      );
    }
    for (final labelId in task.labelIds) {
      final label = labelMap[labelId];
      if (label != null && label.isScoped) continue;
      if (_evaluateRuleContext(
        label?.conditions ?? const [],
        task.conditions,
        locationMap,
        evaluationTime,
        latitude,
        longitude,
      )) {
        return true;
      }
    }
    return false;
  }

  /// Collects all location IDs referenced by [LocationTaskCondition] rules inside [rules].
  static void _collectLocationIdsFromRules(
    List<TaskCondition> rules,
    Set<String> target,
  ) {
    for (final rule in rules) {
      if (rule is LocationTaskCondition) {
        target.addAll(rule.locationIds);
      }
    }
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

  /// Compares two [TdfLocation] instances alphabetically (case-insensitive, then exact, then by ID).
  static int _compareLocationsAlphabetically(
    TdfLocation first,
    TdfLocation second,
  ) {
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
      _incrementLabelCountsForTask(task.labelIds, counts);
    }
    return counts;
  }

  /// Counts open tasks per location across [tasks] (direct or inherited under Section 4.4.3).
  static Map<String, int> _countOpenLocations(
    List<TaskItem> tasks,
    List<TdfLabel> labels,
  ) {
    final counts = <String, int>{};
    final labelMap = <String, TdfLabel>{
      for (final label in labels) label.id: label,
    };
    for (final task in tasks) {
      _incrementLocationCountsForTask(task, labelMap, counts);
    }
    return counts;
  }

  /// Derives a [TdfQueueBlock] preserving the slice order of `[focus, ready, planned, blocked]`.
  static TdfQueueBlock _deriveSliceQueueBlock(
    List<TaskItem> focus,
    List<TaskItem> ready,
    List<TaskItem> planned,
    List<TaskItem> blocked,
  ) {
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

  /// Evaluates all rules belonging to [group] within [rules] using intra-group `OR` short-circuiting.
  static bool _evaluateGroupRules(
    List<TaskCondition> rules,
    ConditionGroup group,
    Map<String, TdfLocation> locationMap,
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
        locations: locationMap,
      )) {
        return true;
      }
    }
    return !hasRuleInGroup;
  }

  /// Evaluates a single effective condition context (`day` AND `time` AND `location`) per Section 4.4.3.
  static bool _evaluateRuleContext(
    List<TaskCondition> baseRules,
    List<TaskCondition> taskRules,
    Map<String, TdfLocation> locationMap,
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
        locationMap,
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
  static bool _hasActiveDeferral(TaskItem task, DateTime nowUtc) =>
      task.isSuspendedForever || (task.suspendedAt?.isAfter(nowUtc) ?? false);

  /// Increments [counts] for each label ID in [labelIds].
  static void _incrementLabelCountsForTask(
    List<String> labelIds,
    Map<String, int> counts,
  ) {
    for (final labelId in labelIds) {
      counts[labelId] = (counts[labelId] ?? 0) + 1;
    }
  }

  /// Increments [counts] for each effective location ID referenced directly or inherited by [task].
  static void _incrementLocationCountsForTask(
    TaskItem task,
    Map<String, TdfLabel> labelMap,
    Map<String, int> counts,
  ) {
    for (final rule in task.conditions) {
      if (rule is GlobalResetTaskCondition) return;
      if (rule is GroupResetTaskCondition &&
          rule.targetGroup == ConditionGroup.location) {
        return;
      }
    }
    final effectiveLocationIds = <String>{};
    _collectLocationIdsFromRules(task.conditions, effectiveLocationIds);
    if (effectiveLocationIds.isEmpty) {
      for (final labelId in task.labelIds) {
        if (labelMap[labelId] case final label?) {
          _collectLocationIdsFromRules(label.conditions, effectiveLocationIds);
        }
      }
    }
    for (final locationId in effectiveLocationIds) {
      counts[locationId] = (counts[locationId] ?? 0) + 1;
    }
  }

  /// Returns whether [timestamp] is strictly older than 30 days (`2,592,000` seconds) relative to [nowUtc].
  static bool _isTimestampExpired(DateTime timestamp, DateTime nowUtc) =>
      nowUtc.difference(timestamp.toUtc()).inSeconds >
      completedRetentionSeconds;

  /// Returns whether [task] is within the 30-day (`2,592,000` seconds) retention window relative to [nowUtc].
  static bool _isWithinRetention(TaskItem task, DateTime nowUtc) {
    final completedDate = task.completedAt;
    return completedDate == null || !_isTimestampExpired(completedDate, nowUtc);
  }

  /// Emits deduplicated `DEBUG` evaluation summary and blocked-task trace entries.
  static void _logDebugEvaluation(
    NormalizedTierSlices slices, {
    required DateTime nowUtc,
    required Map<String, TaskItem> taskMap,
    required String? activeLabelId,
    required double? currentLatitude,
    required double? currentLongitude,
  }) {
    final blockedIds = slices.blocked.map((task) => task.id).join(',');
    final signature =
        '${activeLabelId ?? 'all'}|${slices.focus.length}|'
        '${slices.ready.length}|${slices.planned.length}|'
        '${slices.blocked.length}|${slices.someday.length}|'
        '${slices.completed.length}|$blockedIds';
    if (!AppLogger.deduplicateEvalSummary(signature)) {
      return;
    }
    for (final task in slices.blocked) {
      _logSingleBlockedTask(
        task,
        nowUtc: nowUtc,
        taskMap: taskMap,
        currentLatitude: currentLatitude,
        currentLongitude: currentLongitude,
      );
    }
    AppLogger.event(
      LogLevel.debug,
      LogTag.domain,
      'eval.summary',
      fields: <String, Object?>{
        'label': activeLabelId ?? 'all',
        'focus': slices.focus.length,
        'ready': slices.ready.length,
        'planned': slices.planned.length,
        'blocked': slices.blocked.length,
        'someday': slices.someday.length,
        'completed': slices.completed.length,
      },
    );
  }

  /// Logs the anonymized blocking reason for a single [task] at `DEBUG` level.
  static void _logSingleBlockedTask(
    TaskItem task, {
    required DateTime nowUtc,
    required Map<String, TaskItem> taskMap,
    required double? currentLatitude,
    required double? currentLongitude,
  }) {
    final hasDeferral = _hasActiveDeferral(task, nowUtc);
    final depsOk = areDependenciesSatisfied(task, taskMap);
    final reason = hasDeferral
        ? 'deferral'
        : (!depsOk ? 'dependency' : 'condition');
    int? distanceMeters;
    int? radiusMeters;
    if (reason == 'condition' &&
        currentLatitude != null &&
        currentLongitude != null) {
      for (final rule in task.conditions) {
        if (rule is LocationTaskCondition) {
          distanceMeters = LocationTaskCondition.haversineDistanceMeters(
            currentLatitude,
            currentLongitude,
            rule.latitude,
            rule.longitude,
          ).round();
          radiusMeters = rule.radiusMeters.round();
          break;
        }
      }
    }
    AppLogger.event(
      LogLevel.debug,
      LogTag.domain,
      'eval.blocked',
      fields: <String, Object?>{
        'id': task.id,
        'reason': reason,
        'distance_m': distanceMeters,
        'radius_m': radiusMeters,
      },
    );
  }

  /// Maps a legacy domain mutation verb to its canonical `<domain>.<verb>` event name.
  static String _mapDomainVerb(String rawVerb) {
    if (rawVerb.startsWith('completeTask')) return 'task.complete';
    return switch (rawVerb) {
      'addTask' => 'task.add',
      'updateTask' => 'task.update',
      'restoreTask' => 'task.restore',
      'deleteTask' => 'task.delete',
      'downgradeTask' => 'task.downgrade',
      'scheduleTask' => 'task.schedule',
      'blockTask' => 'task.block',
      'moveTaskInQueue' => 'task.move_queue',
      'toggleSubtask' => 'task.toggle_subtask',
      'addLabel' => 'label.add',
      'updateLabel' => 'label.update',
      'deleteLabel' => 'label.delete',
      'addLocation' => 'location.add',
      'updateLocation' => 'location.update',
      'deleteLocation' => 'location.delete',
      _ => rawVerb,
    };
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
      if (eligibleById[taskId] case final task? when visited.add(taskId)) {
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

  /// Strips prerequisite dependencies in [task] targeting any ID in [expiredTaskIds] and advances `modifiedAt` when changed per Section 6.8.3.
  static TaskItem _stripExpiredTaskDependencies(
    TaskItem task,
    Set<String> expiredTaskIds,
    DateTime now,
  ) {
    if (!task.dependencies.any((dep) => expiredTaskIds.contains(dep.taskId))) {
      return task;
    }
    final remaining = <TdfTaskDependency>[
      for (final dep in task.dependencies)
        if (!expiredTaskIds.contains(dep.taskId)) dep,
    ];
    return task.copyWith(
      dependencies: remaining,
      modifiedAt: TaskItem.nextModifiedTimestamp(now, task.effectiveModifiedAt),
    );
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
