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
import 'task_item.dart';
import 'tdf_location.dart';
import 'tdf_metadata.dart';
import 'tdf_payload_comparison.dart';
import 'tdf_sync_metadata.dart';
import 'tdf_timezone.dart';

/// Result of applying inline `TDF-REC-002` recovery rewrites to merge sides.
typedef InlineRecoveryRewrite = ({
  TaskBoard primary,
  TaskBoard secondary,
  Set<String> freshlyRecoveredLocationIds,
  Set<String> freshlyRecoveredLabelIds,
  Set<String> freshlyRecoveredTaskIds,
  Set<String> rewrittenLabelIds,
  Set<String> rewrittenTaskIds,
  Set<String> discardedTaskIds,
});

/// Prepared stale board and rewritten ID tracking produced by [TaskBoardRecovery.prepareBoardForRecovery].
typedef PreparedRecoveryBoard = ({
  TaskBoard board,
  Set<String> freshlyRecoveredLocationIds,
  Set<String> freshlyRecoveredLabelIds,
  Set<String> freshlyRecoveredTaskIds,
  Set<String> rewrittenLabelIds,
  Set<String> rewrittenTaskIds,
  Set<String> discardedTaskIds,
});

/// Stateless `TDF-REC-001` / `TDF-REC-002` entity recovery rewriting and tombstone retention helper.
@immutable
class TaskBoardRecovery {
  /// Prevents instantiation of this stateless helper class.
  const TaskBoardRecovery._();

  /// Rewrites `recoverAsNew` entities on the stale side when inline recovery resolutions are passed directly to `TaskBoardSync.merge`.
  static InlineRecoveryRewrite applyInlineRecoveryRewrite({
    required TaskBoard primary,
    required TaskBoard secondary,
    required TaskBoard? baseline,
    required bool primaryRefresh,
    required bool secondaryRefresh,
    required Map<String, TdfRecoveryResolution> taskRecoveryResolutions,
    required Map<String, TdfRecoveryResolution> labelRecoveryResolutions,
    required Map<String, TdfRecoveryResolution> locationRecoveryResolutions,
    required DateTime now,
    required DateTime? localEvaluationTime,
    required TdfTimeZoneContext? timeZone,
    required Duration? dueLeadWindow,
  }) {
    final hasNewTask = _hasAnyRecoverAsNew(taskRecoveryResolutions);
    final hasNewLabel = _hasAnyRecoverAsNew(labelRecoveryResolutions);
    final hasNewLocation = _hasAnyRecoverAsNew(locationRecoveryResolutions);
    if (!hasNewTask && !hasNewLabel && !hasNewLocation) {
      return (
        primary: primary,
        secondary: secondary,
        freshlyRecoveredLocationIds: const <String>{},
        freshlyRecoveredLabelIds: const <String>{},
        freshlyRecoveredTaskIds: const <String>{},
        rewrittenLabelIds: const <String>{},
        rewrittenTaskIds: const <String>{},
        discardedTaskIds: const <String>{},
      );
    }
    final recoverLocs = resolveRecoverIdSet(locationRecoveryResolutions);
    final recoverLabels = resolveRecoverIdSet(labelRecoveryResolutions);
    final recoverTasks = resolveRecoverIdSet(taskRecoveryResolutions);
    var currentPrimary = primary;
    var currentSecondary = secondary;
    final freshlyRecoveredLocationIds = <String>{};
    final freshlyRecoveredLabelIds = <String>{};
    final freshlyRecoveredTaskIds = <String>{};
    final rewrittenLabelIds = <String>{};
    final rewrittenTaskIds = <String>{};
    final discardedTaskIds = <String>{};

    if (primaryRefresh) {
      final prepared = prepareBoardForRecovery(
        staleBoard: currentPrimary,
        advancedBoard: currentSecondary,
        baseline: baseline,
        recoverLocationIds: recoverLocs,
        recoverLabelIds: recoverLabels,
        recoverTaskIds: recoverTasks,
        discardAllUnrecoveredStaleOnly: false,
        explicitTaskResolutions: taskRecoveryResolutions,
        explicitLabelResolutions: labelRecoveryResolutions,
        explicitLocationResolutions: locationRecoveryResolutions,
        now: now,
        localEvaluationTime: localEvaluationTime,
        timeZone: timeZone,
        dueLeadWindow: dueLeadWindow,
      );
      currentPrimary = prepared.board;
      freshlyRecoveredLocationIds.addAll(prepared.freshlyRecoveredLocationIds);
      freshlyRecoveredLabelIds.addAll(prepared.freshlyRecoveredLabelIds);
      freshlyRecoveredTaskIds.addAll(prepared.freshlyRecoveredTaskIds);
      rewrittenLabelIds.addAll(prepared.rewrittenLabelIds);
      rewrittenTaskIds.addAll(prepared.rewrittenTaskIds);
      discardedTaskIds.addAll(prepared.discardedTaskIds);
    }
    if (secondaryRefresh) {
      final prepared = prepareBoardForRecovery(
        staleBoard: currentSecondary,
        advancedBoard: currentPrimary,
        baseline: baseline,
        recoverLocationIds: recoverLocs,
        recoverLabelIds: recoverLabels,
        recoverTaskIds: recoverTasks,
        discardAllUnrecoveredStaleOnly: false,
        explicitTaskResolutions: taskRecoveryResolutions,
        explicitLabelResolutions: labelRecoveryResolutions,
        explicitLocationResolutions: locationRecoveryResolutions,
        now: now,
        localEvaluationTime: localEvaluationTime,
        timeZone: timeZone,
        dueLeadWindow: dueLeadWindow,
      );
      currentSecondary = prepared.board;
      freshlyRecoveredLocationIds.addAll(prepared.freshlyRecoveredLocationIds);
      freshlyRecoveredLabelIds.addAll(prepared.freshlyRecoveredLabelIds);
      freshlyRecoveredTaskIds.addAll(prepared.freshlyRecoveredTaskIds);
      rewrittenLabelIds.addAll(prepared.rewrittenLabelIds);
      rewrittenTaskIds.addAll(prepared.rewrittenTaskIds);
      discardedTaskIds.addAll(prepared.discardedTaskIds);
    }
    return (
      primary: currentPrimary,
      secondary: currentSecondary,
      freshlyRecoveredLocationIds: freshlyRecoveredLocationIds,
      freshlyRecoveredLabelIds: freshlyRecoveredLabelIds,
      freshlyRecoveredTaskIds: freshlyRecoveredTaskIds,
      rewrittenLabelIds: rewrittenLabelIds,
      rewrittenTaskIds: rewrittenTaskIds,
      discardedTaskIds: discardedTaskIds,
    );
  }

  /// Returns whether label deletion [record] was already acknowledged in [baseline] when [discard] is true.
  static bool isAckedLabel(
    TdfDeletedLabelRecord record,
    TdfDeletedBlock? baseline,
    bool discard,
  ) {
    if (!discard || baseline == null) {
      return false;
    }
    final baselineAt = baseline.findLabelRecord(record.labelId)?.deletedAt;
    return baselineAt != null && !record.deletedAt.isAfter(baselineAt);
  }

  /// Returns whether location deletion [record] was already acknowledged in [baseline] when [discard] is true.
  static bool isAckedLocation(
    TdfDeletedLocationRecord record,
    TdfDeletedBlock? baseline,
    bool discard,
  ) {
    if (!discard || baseline == null) {
      return false;
    }
    final baselineAt = baseline
        .findLocationRecord(record.locationId)
        ?.deletedAt;
    return baselineAt != null && !record.deletedAt.isAfter(baselineAt);
  }

  /// Returns whether task deletion [record] was already acknowledged in [baseline] when [discard] is true.
  static bool isAckedTask(
    TdfDeletedTaskRecord record,
    TdfDeletedBlock? baseline,
    bool discard,
  ) {
    if (!discard || baseline == null) {
      return false;
    }
    final baselineAt = baseline.findTaskRecord(record.taskId)?.deletedAt;
    return baselineAt != null && !record.deletedAt.isAfter(baselineAt);
  }

  /// Returns whether a deletion record with [deletedAt] has expired at [now] when [prune] is true.
  static bool isDeletedRecordExpired(
    DateTime deletedAt,
    DateTime now,
    bool prune,
  ) =>
      prune &&
      now.difference(deletedAt).inSeconds > TaskBoard.completedRetentionSeconds;

  /// Prepares [staleBoard] for `TDF-REC-002` recovery by rewriting `recoverAsNew` IDs and stripping discarded stale-only references.
  static PreparedRecoveryBoard prepareBoardForRecovery({
    required TaskBoard staleBoard,
    required TaskBoard advancedBoard,
    required TaskBoard? baseline,
    required Set<String> recoverLocationIds,
    required Set<String> recoverLabelIds,
    required Set<String> recoverTaskIds,
    required bool discardAllUnrecoveredStaleOnly,
    Map<String, TdfRecoveryResolution> explicitTaskResolutions = const {},
    Map<String, TdfRecoveryResolution> explicitLabelResolutions = const {},
    Map<String, TdfRecoveryResolution> explicitLocationResolutions = const {},
    required DateTime now,
    required DateTime? localEvaluationTime,
    required TdfTimeZoneContext? timeZone,
    required Duration? dueLeadWindow,
  }) {
    final usedIds = _collectUsedIdsForRecovery(
      staleBoard,
      advancedBoard,
      baseline,
    );
    final staleLocationIds = <String>{
      for (final location in staleBoard.locations) location.id,
    };
    final staleLabelIds = <String>{
      for (final label in staleBoard.labels) label.id,
    };
    final staleTaskIds = <String>{
      for (final task in staleBoard.allTasks) task.id,
    };
    final advancedLocationIds = <String>{
      for (final location in advancedBoard.locations) location.id,
    };
    final advancedLabelIds = <String>{
      for (final label in advancedBoard.labels) label.id,
    };
    final advancedTaskIds = <String>{
      for (final task in advancedBoard.allTasks) task.id,
    };

    final locationIdMap = _buildRecoveredIdMap(
      recoverIds: recoverLocationIds,
      staleIds: staleLocationIds,
      advancedIds: advancedLocationIds,
      usedIds: usedIds.locations,
      now: now,
    );
    final labelIdMap = _buildRecoveredIdMap(
      recoverIds: recoverLabelIds,
      staleIds: staleLabelIds,
      advancedIds: advancedLabelIds,
      usedIds: usedIds.labels,
      now: now,
    );
    final taskIdMap = _buildRecoveredIdMap(
      recoverIds: recoverTaskIds,
      staleIds: staleTaskIds,
      advancedIds: advancedTaskIds,
      usedIds: usedIds.tasks,
      now: now,
    );

    final discardedLocationIds = _buildDiscardedIds(
      staleIds: staleLocationIds,
      recoveredIdMap: locationIdMap,
      advancedIds: advancedLocationIds,
      hasAdvancedTombstone: (id) =>
          advancedBoard.deletedBlock.findLocationRecord(id) != null,
      discardAllUnrecoveredStaleOnly: discardAllUnrecoveredStaleOnly,
      explicitResolutions: explicitLocationResolutions,
    );
    final discardedLabelIds = _buildDiscardedIds(
      staleIds: staleLabelIds,
      recoveredIdMap: labelIdMap,
      advancedIds: advancedLabelIds,
      hasAdvancedTombstone: (id) =>
          advancedBoard.deletedBlock.findLabelRecord(id) != null,
      discardAllUnrecoveredStaleOnly: discardAllUnrecoveredStaleOnly,
      explicitResolutions: explicitLabelResolutions,
    );
    final discardedTaskIds = _buildDiscardedIds(
      staleIds: staleTaskIds,
      recoveredIdMap: taskIdMap,
      advancedIds: advancedTaskIds,
      hasAdvancedTombstone: (id) =>
          advancedBoard.deletedBlock.findTaskRecord(id) != null,
      discardAllUnrecoveredStaleOnly: discardAllUnrecoveredStaleOnly,
      explicitResolutions: explicitTaskResolutions,
    );

    final adjustedLocations = <TdfLocation>[
      for (final location in staleBoard.locations)
        if (locationIdMap[location.id] case final newId?)
          location.copyWith(
            id: newId,
            modifiedAt: TaskItem.nextModifiedTimestamp(
              now,
              location.effectiveModifiedAt,
            ),
          )
        else if (!discardedLocationIds.contains(location.id))
          location,
    ];

    final rewrittenLabelIds = <String>{};
    final adjustedLabels = <TdfLabel>[
      for (final label in staleBoard.labels)
        if (labelIdMap[label.id] case final newId?)
          _rewriteAndStripLabel(
            label,
            newId: newId,
            isNewEntity: true,
            locationIdMap: locationIdMap,
            discardedLocationIds: discardedLocationIds,
            now: now,
            rewrittenSharedOut: null,
          )
        else if (!discardedLabelIds.contains(label.id))
          _rewriteAndStripLabel(
            label,
            newId: label.id,
            isNewEntity: false,
            locationIdMap: locationIdMap,
            discardedLocationIds: discardedLocationIds,
            now: now,
            rewrittenSharedOut: rewrittenLabelIds,
          ),
    ];

    final effectiveLabelsById = <String, TdfLabel>{
      for (final label in advancedBoard.labels) label.id: label,
      for (final label in adjustedLabels) label.id: label,
    };
    final scopedBeforeIds = <String>{
      for (final label in staleBoard.labels)
        if (label.isScoped) label.id,
      for (final label in advancedBoard.labels)
        if (label.isScoped) label.id,
      if (baseline != null)
        for (final label in baseline.labels)
          if (label.isScoped) label.id,
    };

    final rewrittenTaskIds = <String>{};
    final evictedQueueIds = <String>{};
    final adjustedTasks = <TaskItem>[
      for (final task in staleBoard.allTasks)
        if (taskIdMap[task.id] case final newId?)
          _rewriteAndStripTask(
            task,
            newId: newId,
            isNewEntity: true,
            labelIdMap: labelIdMap,
            taskIdMap: taskIdMap,
            locationIdMap: locationIdMap,
            discardedLabelIds: discardedLabelIds,
            discardedTaskIds: discardedTaskIds,
            discardedLocationIds: discardedLocationIds,
            effectiveLabelsById: effectiveLabelsById,
            scopedBeforeIds: scopedBeforeIds,
            now: now,
            rewrittenSharedOut: null,
            evictedQueueOut: evictedQueueIds,
          )
        else if (!discardedTaskIds.contains(task.id))
          _rewriteAndStripTask(
            task,
            newId: task.id,
            isNewEntity: false,
            labelIdMap: labelIdMap,
            taskIdMap: taskIdMap,
            locationIdMap: locationIdMap,
            discardedLabelIds: discardedLabelIds,
            discardedTaskIds: discardedTaskIds,
            discardedLocationIds: discardedLocationIds,
            effectiveLabelsById: effectiveLabelsById,
            scopedBeforeIds: scopedBeforeIds,
            now: now,
            rewrittenSharedOut: rewrittenTaskIds,
            evictedQueueOut: evictedQueueIds,
          ),
    ];

    final survivingTaskIdSet = <String>{
      for (final task in adjustedTasks) task.id,
    };
    final adjustedQueueIds = <String>[
      for (final id in staleBoard.queueBlock.taskIds)
        if (taskIdMap[id] case final mapped?
            when !evictedQueueIds.contains(mapped) &&
                survivingTaskIdSet.contains(mapped))
          mapped
        else if (!discardedTaskIds.contains(id) &&
            !evictedQueueIds.contains(id) &&
            survivingTaskIdSet.contains(id))
          id,
    ];

    final preparedBoard = TaskBoard.evaluate(
      tasks: adjustedTasks,
      labels: adjustedLabels,
      locations: adjustedLocations,
      deletedBlock: discardAllUnrecoveredStaleOnly
          ? _filterStaleDeletedBlockForRecovery(
              staleDeleted: staleBoard.deletedBlock,
              advancedBoard: advancedBoard,
              baselineDeleted: baseline?.deletedBlock,
              now: now,
            )
          : staleBoard.deletedBlock,
      queueBlock: staleBoard.queueBlock.copyWith(taskIds: adjustedQueueIds),
      evaluationTime: now,
      localEvaluationTime: localEvaluationTime,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
    );
    return (
      board: preparedBoard,
      freshlyRecoveredLocationIds: locationIdMap.values.toSet(),
      freshlyRecoveredLabelIds: labelIdMap.values.toSet(),
      freshlyRecoveredTaskIds: taskIdMap.values.toSet(),
      rewrittenLabelIds: rewrittenLabelIds,
      rewrittenTaskIds: rewrittenTaskIds,
      discardedTaskIds: discardedTaskIds,
    );
  }

  /// Collects entity IDs selected for `recoverAsNew` in [resolutions].
  static Set<String> resolveRecoverIdSet(
    Map<String, TdfRecoveryResolution> resolutions,
  ) {
    return <String>{
      for (final entry in resolutions.entries)
        if (entry.value == TdfRecoveryResolution.recoverAsNew) entry.key,
    };
  }

  /// Collects stale-only entity IDs that should be discarded during recovery rewriting.
  static Set<String> _buildDiscardedIds({
    required Set<String> staleIds,
    required Map<String, String> recoveredIdMap,
    required Set<String> advancedIds,
    required bool Function(String id) hasAdvancedTombstone,
    required bool discardAllUnrecoveredStaleOnly,
    required Map<String, TdfRecoveryResolution> explicitResolutions,
  }) {
    return <String>{
      for (final id in staleIds)
        if (!recoveredIdMap.containsKey(id) &&
            !advancedIds.contains(id) &&
            !hasAdvancedTombstone(id) &&
            (discardAllUnrecoveredStaleOnly ||
                explicitResolutions[id] == TdfRecoveryResolution.discard))
          id,
    };
  }

  /// Generates collision-free replacement 10-character Base62 IDs for eligible [recoverIds].
  static Map<String, String> _buildRecoveredIdMap({
    required Set<String> recoverIds,
    required Set<String> staleIds,
    required Set<String> advancedIds,
    required Set<String> usedIds,
    required DateTime now,
  }) {
    final mapped = <String, String>{};
    for (final oldId in recoverIds) {
      if (!staleIds.contains(oldId) || advancedIds.contains(oldId)) {
        continue;
      }
      final newId = TdfEntityId.generate(timestamp: now, existingIds: usedIds);
      usedIds.add(newId);
      mapped[oldId] = newId;
    }
    return mapped;
  }

  /// Collects `<location-id>` tokens from [conditions] into [target].
  static void _collectBoardLocationRefIds(
    List<TaskCondition> conditions,
    Set<String> target,
  ) {
    for (final rule in conditions) {
      if (rule is LocationTaskCondition && rule.locationIds.isNotEmpty) {
        target.addAll(rule.locationIds);
      }
    }
  }

  /// Collects referenced task, label, and location IDs across [board] into [usedTaskIds], [usedLabelIds], and [usedLocationIds].
  static void _collectBoardTaskAndLabelRefIds(
    TaskBoard board,
    Set<String> usedTaskIds,
    Set<String> usedLabelIds,
    Set<String> usedLocationIds,
  ) {
    for (final location in board.locations) {
      usedLocationIds.add(location.id);
    }
    for (final record in board.deletedBlock.locations) {
      usedLocationIds.add(record.locationId);
    }
    for (final label in board.labels) {
      usedLabelIds.add(label.id);
      _collectBoardLocationRefIds(label.conditions, usedLocationIds);
    }
    for (final record in board.deletedBlock.labels) {
      usedLabelIds.add(record.labelId);
    }
    for (final task in board.allTasks) {
      usedTaskIds.add(task.id);
      usedLabelIds.addAll(task.labelIds);
      _collectDependencyTargetIds(task.dependencies, usedTaskIds);
      _collectBoardLocationRefIds(task.conditions, usedLocationIds);
    }
    for (final record in board.deletedBlock.tasks) {
      usedTaskIds.add(record.taskId);
    }
    usedTaskIds.addAll(board.queueBlock.taskIds);
  }

  /// Collects prerequisite `<task-id>` targets from [dependencies] into [target].
  static void _collectDependencyTargetIds(
    List<TdfTaskDependency> dependencies,
    Set<String> target,
  ) {
    for (final dependency in dependencies) {
      target.add(dependency.taskId);
    }
  }

  /// Collects collision-free ID sets across [staleBoard], [advancedBoard], and [baseline] (`TDF-ID-001` Step 4).
  static ({Set<String> locations, Set<String> labels, Set<String> tasks})
  _collectUsedIdsForRecovery(
    TaskBoard staleBoard,
    TaskBoard advancedBoard,
    TaskBoard? baseline,
  ) {
    final usedLocations = <String>{};
    final usedLabels = <String>{};
    final usedTasks = <String>{};
    _collectBoardTaskAndLabelRefIds(
      staleBoard,
      usedTasks,
      usedLabels,
      usedLocations,
    );
    _collectBoardTaskAndLabelRefIds(
      advancedBoard,
      usedTasks,
      usedLabels,
      usedLocations,
    );
    if (baseline != null) {
      _collectBoardTaskAndLabelRefIds(
        baseline,
        usedTasks,
        usedLabels,
        usedLocations,
      );
    }
    return (locations: usedLocations, labels: usedLabels, tasks: usedTasks);
  }

  /// Filters superseded acknowledged tombstones out of [staleDeleted] before adopting [advancedBoard]'s generation (`TDF-REC-001` Step 4).
  static TdfDeletedBlock _filterStaleDeletedBlockForRecovery({
    required TdfDeletedBlock staleDeleted,
    required TaskBoard advancedBoard,
    required TdfDeletedBlock? baselineDeleted,
    required DateTime now,
  }) {
    final advancedTaskIds = <String>{
      for (final task in advancedBoard.allTasks) task.id,
    };
    final advancedLabelIds = <String>{
      for (final label in advancedBoard.labels) label.id,
    };
    final advancedLocationIds = <String>{
      for (final location in advancedBoard.locations) location.id,
    };
    final retainedTasks = <TdfDeletedTaskRecord>[
      for (final record in staleDeleted.tasks)
        if (baselineDeleted != null
            ? !isAckedTask(record, baselineDeleted, true)
            : (!advancedTaskIds.contains(record.taskId) &&
                  !isDeletedRecordExpired(record.deletedAt, now, true)))
          record,
    ];
    final retainedLabels = <TdfDeletedLabelRecord>[
      for (final record in staleDeleted.labels)
        if (baselineDeleted != null
            ? !isAckedLabel(record, baselineDeleted, true)
            : (!advancedLabelIds.contains(record.labelId) &&
                  !isDeletedRecordExpired(record.deletedAt, now, true)))
          record,
    ];
    final retainedLocations = <TdfDeletedLocationRecord>[
      for (final record in staleDeleted.locations)
        if (baselineDeleted != null
            ? !isAckedLocation(record, baselineDeleted, true)
            : (!advancedLocationIds.contains(record.locationId) &&
                  !isDeletedRecordExpired(record.deletedAt, now, true)))
          record,
    ];
    return TdfDeletedBlock(
      generation: advancedBoard.deletedBlock.generation,
      tasks: retainedTasks,
      labels: retainedLabels,
      locations: retainedLocations,
    );
  }

  /// Returns whether [resolutions] contains at least one [TdfRecoveryResolution.recoverAsNew] entry.
  static bool _hasAnyRecoverAsNew(
    Map<String, TdfRecoveryResolution> resolutions,
  ) {
    for (final resolution in resolutions.values) {
      if (resolution == TdfRecoveryResolution.recoverAsNew) {
        return true;
      }
    }
    return false;
  }

  /// Returns whether any label in [labelIds] carries a non-empty `LocationTaskCondition` in [labelsById].
  static bool _hasLiveLabelLocationRule(
    List<String> labelIds,
    Map<String, TdfLabel> labelsById,
  ) {
    for (final labelId in labelIds) {
      final label = labelsById[labelId];
      if (label != null &&
          TdfMetadata.hasLocationConditionRule(label.conditions)) {
        return true;
      }
    }
    return false;
  }

  /// Remaps [locationIds] via [locationIdMap] while omitting [discardedLocationIds].
  static ({List<String> mappedIds, bool changed}) _mapAndFilterLocationIds(
    List<String> locationIds,
    Map<String, String> locationIdMap,
    Set<String> discardedLocationIds,
  ) {
    final mappedIds = <String>[];
    var changed = false;
    for (final locId in locationIds) {
      if (discardedLocationIds.contains(locId)) {
        changed = true;
        continue;
      }
      final mapped = locationIdMap[locId];
      if (mapped != null) {
        changed = true;
        mappedIds.add(mapped);
      } else {
        mappedIds.add(locId);
      }
    }
    return (mappedIds: mappedIds, changed: changed);
  }

  /// Rewrites `condition location` references via [locationIdMap] and strips [discardedLocationIds] on [label] during recovery (`TDF-REC-002`).
  static TdfLabel _rewriteAndStripLabel(
    TdfLabel label, {
    required String newId,
    required bool isNewEntity,
    required Map<String, String> locationIdMap,
    required Set<String> discardedLocationIds,
    required DateTime now,
    required Set<String>? rewrittenSharedOut,
  }) {
    final updatedConditions = <TaskCondition>[];
    var conditionsChanged = false;
    for (final rule in label.conditions) {
      if (rule is! LocationTaskCondition || rule.locationIds.isEmpty) {
        updatedConditions.add(rule);
        continue;
      }
      final mapped = _mapAndFilterLocationIds(
        rule.locationIds,
        locationIdMap,
        discardedLocationIds,
      );
      if (mapped.changed) {
        conditionsChanged = true;
      }
      if (mapped.mappedIds.isNotEmpty) {
        updatedConditions.add(LocationTaskCondition.fromIds(mapped.mappedIds));
      }
    }

    if (!isNewEntity && !conditionsChanged) {
      return label;
    }
    if (!isNewEntity) {
      rewrittenSharedOut?.add(newId);
      return label.copyWith(conditions: updatedConditions);
    }
    return label.copyWith(
      id: newId,
      modifiedAt: TaskItem.nextModifiedTimestamp(
        now,
        label.effectiveModifiedAt,
      ),
      conditions: conditionsChanged ? updatedConditions : label.conditions,
    );
  }

  /// Rewrites recovered IDs and strips discarded label, task, and location references on [task] during recovery (`TDF-REC-002`).
  static TaskItem _rewriteAndStripTask(
    TaskItem task, {
    required String newId,
    required bool isNewEntity,
    required Map<String, String> labelIdMap,
    required Map<String, String> taskIdMap,
    required Map<String, String> locationIdMap,
    required Set<String> discardedLabelIds,
    required Set<String> discardedTaskIds,
    required Set<String> discardedLocationIds,
    required Map<String, TdfLabel> effectiveLabelsById,
    required Set<String> scopedBeforeIds,
    required DateTime now,
    required Set<String>? rewrittenSharedOut,
    required Set<String>? evictedQueueOut,
  }) {
    final isOpen = !task.isCompleted && task.completedAt == null;
    var labelsChanged = false;
    var strippedDiscardedLabel = false;
    final allBeforeWereScoped =
        task.labelIds.isNotEmpty &&
        task.labelIds.every(scopedBeforeIds.contains);
    final rawMappedLabels = <String>[];
    for (final labelId in task.labelIds) {
      if (discardedLabelIds.contains(labelId)) {
        labelsChanged = true;
        strippedDiscardedLabel = true;
        continue;
      }
      final mapped = labelIdMap[labelId];
      if (mapped != null) {
        labelsChanged = true;
        rawMappedLabels.add(mapped);
      } else {
        rawMappedLabels.add(labelId);
      }
    }
    final nextLabels = labelsChanged
        ? TdfPayloadComparison.normalizedLabelSet(rawMappedLabels)
        : task.labelIds;
    final lostLastScoped =
        isOpen &&
        strippedDiscardedLabel &&
        allBeforeWereScoped &&
        nextLabels.isEmpty;
    if (lostLastScoped) {
      evictedQueueOut?.add(newId);
    }
    final nextPriority = !lostLastScoped && task.isPriority;

    var depsChanged = false;
    final rawMappedDeps = <TdfTaskDependency>[];
    for (final dependency in task.dependencies) {
      if (isOpen && discardedTaskIds.contains(dependency.taskId)) {
        depsChanged = true;
        continue;
      }
      final mappedTarget = taskIdMap[dependency.taskId];
      if (mappedTarget != null) {
        depsChanged = true;
        rawMappedDeps.add(
          TdfTaskDependency(
            taskId: mappedTarget,
            requiredCompletion: dependency.requiredCompletion,
          ),
        );
      } else {
        rawMappedDeps.add(dependency);
      }
    }
    final nextDeps = depsChanged
        ? TdfTaskDependency.normalizeList(rawMappedDeps)
        : task.dependencies;

    final condResult = _rewriteTaskConditionsForRecovery(
      task.conditions,
      nextLabels: nextLabels,
      locationIdMap: locationIdMap,
      discardedLocationIds: discardedLocationIds,
      effectiveLabelsById: effectiveLabelsById,
    );

    final anyPayloadChange =
        labelsChanged ||
        depsChanged ||
        condResult.changed ||
        nextPriority != task.isPriority;
    if (!isNewEntity && !anyPayloadChange) {
      return task;
    }
    if (!isNewEntity) {
      rewrittenSharedOut?.add(newId);
    }
    return task.copyWith(
      id: newId,
      isPriority: nextPriority,
      modifiedAt: isNewEntity
          ? TaskItem.nextModifiedTimestamp(now, task.effectiveModifiedAt)
          : task.modifiedAt,
      labelIds: nextLabels,
      conditions: condResult.changed ? condResult.conditions : task.conditions,
      dependencies: nextDeps,
      blockedByTaskIds: <String>[
        for (final dependency in nextDeps) dependency.taskId,
      ],
    );
  }

  /// Rewrites `condition location` references via [locationIdMap] and strips [discardedLocationIds] on task [conditions] (`TDF-REC-002`).
  static ({List<TaskCondition> conditions, bool changed})
  _rewriteTaskConditionsForRecovery(
    List<TaskCondition> conditions, {
    required List<String> nextLabels,
    required Map<String, String> locationIdMap,
    required Set<String> discardedLocationIds,
    required Map<String, TdfLabel> effectiveLabelsById,
  }) {
    if (conditions.isEmpty ||
        (locationIdMap.isEmpty && discardedLocationIds.isEmpty)) {
      return (conditions: conditions, changed: false);
    }
    final updated = <TaskCondition>[];
    var changed = false;
    for (final rule in conditions) {
      if (rule is! LocationTaskCondition || rule.locationIds.isEmpty) {
        updated.add(rule);
        continue;
      }
      final mapped = _mapAndFilterLocationIds(
        rule.locationIds,
        locationIdMap,
        discardedLocationIds,
      );
      if (mapped.changed) {
        changed = true;
      }
      if (mapped.mappedIds.isNotEmpty) {
        updated.add(LocationTaskCondition.fromIds(mapped.mappedIds));
      } else if (_hasLiveLabelLocationRule(nextLabels, effectiveLabelsById)) {
        updated.add(
          const GroupResetTaskCondition(targetGroup: ConditionGroup.location),
        );
      }
    }
    return (conditions: updated, changed: changed);
  }
}
