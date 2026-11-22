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

/// Stateless domain algorithms for scoping optimistic merge candidates and baselines
/// to their pre-mutation origin across concurrent reconciles, block cleanups, and generation advances.
@immutable
class TaskBoardSyncScoping {
  /// Prevents instantiation of [TaskBoardSyncScoping].
  const TaskBoardSyncScoping._();

  /// Aligns [candidate], [storedBaseline], and [storedAckGeneration] against [candidateOriginBoard]
  /// across concurrent reconciles, automatic block cleanups, and acknowledged generation bumps.
  static ({TaskBoard candidate, TaskBoard? baseline, int? ackGeneration})
  scopeCandidateAndBaseline({
    required TaskBoard candidate,
    required bool hasCandidate,
    required TaskBoard? storedBaseline,
    required TaskBoard? candidateOriginBoard,
    required int? storedAckGeneration,
    required DateTime utcNow,
    required DateTime localNow,
    required TdfTimeZoneContext timeZone,
    required Duration? dueLeadWindow,
  }) {
    if (!hasCandidate || candidateOriginBoard == null) {
      return (
        candidate: candidate,
        baseline: storedBaseline,
        ackGeneration: storedAckGeneration,
      );
    }
    final originTasks = <String, TaskItem>{
      for (final item in candidateOriginBoard.allTasks) item.id: item,
    };
    final candidateTasksById = <String, TaskItem>{
      for (final item in candidate.allTasks) item.id: item,
    };
    final candidateDeletedTaskIds = <String>{
      for (final record in candidate.deletedBlock.tasks) record.taskId,
    };
    var rebasedCandidate = _restorePreCleanupBystanderTasks(
      candidate: candidate,
      candidateOriginBoard: candidateOriginBoard,
      storedBaseline: storedBaseline,
      originTasks: originTasks,
      candidateTasksById: candidateTasksById,
      candidateDeletedTaskIds: candidateDeletedTaskIds,
      utcNow: utcNow,
      localNow: localNow,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
    );
    if (storedBaseline == null) {
      return (
        candidate: rebasedCandidate,
        baseline: null,
        ackGeneration: storedAckGeneration,
      );
    }
    final originLabels = <String, TdfLabel>{
      for (final label in candidateOriginBoard.labels) label.id: label,
    };
    final originLocations = <String, TdfLocation>{
      for (final location in candidateOriginBoard.locations)
        location.id: location,
    };
    final originGeneration = candidateOriginBoard.deletedBlock.generation;
    final storedGeneration = storedBaseline.deletedBlock.generation;
    final resolvedAckGeneration = storedAckGeneration ?? storedGeneration;
    var useOriginGeneration = false;
    var effectiveAckGeneration = resolvedAckGeneration;

    if (originGeneration < storedGeneration &&
        storedGeneration <= resolvedAckGeneration) {
      final retiredTaskIds = <String>{
        for (final id in originTasks.keys)
          if (storedBaseline.findTask(id) == null &&
              storedBaseline.deletedBlock.findTaskRecord(id) == null)
            id,
      };
      final retiredLabelIds = <String>{
        for (final id in originLabels.keys)
          if (storedBaseline.findLabel(id) == null &&
              storedBaseline.deletedBlock.findLabelRecord(id) == null)
            id,
      };
      final retiredLocationIds = <String>{
        for (final id in originLocations.keys)
          if (storedBaseline.findLocation(id) == null &&
              storedBaseline.deletedBlock.findLocationRecord(id) == null)
            id,
      };
      if (_didCandidateModifyRetiredEntities(
        candidate,
        originTasks: originTasks,
        originLabels: originLabels,
        originLocations: originLocations,
        candidateTasksById: candidateTasksById,
        candidateDeletedTaskIds: candidateDeletedTaskIds,
        retiredTaskIds: retiredTaskIds,
        retiredLabelIds: retiredLabelIds,
        retiredLocationIds: retiredLocationIds,
        utcNow: utcNow,
      )) {
        useOriginGeneration = true;
        effectiveAckGeneration = originGeneration;
      } else if (rebasedCandidate.deletedBlock.generation == originGeneration) {
        rebasedCandidate = _rebaseCandidateToGeneration(
          rebasedCandidate,
          targetGeneration: storedGeneration,
          retiredTaskIds: retiredTaskIds,
          retiredLabelIds: retiredLabelIds,
          retiredLocationIds: retiredLocationIds,
          utcNow: utcNow,
          localNow: localNow,
          timeZone: timeZone,
          dueLeadWindow: dueLeadWindow,
        );
      }
    } else if (originGeneration < resolvedAckGeneration) {
      useOriginGeneration = originGeneration < storedGeneration;
      effectiveAckGeneration = originGeneration;
    }

    final scopedBaseline = _scopeBaselineToCandidateOrigin(
      storedBaseline,
      candidateOriginBoard,
      originTasks: originTasks,
      originLabels: originLabels,
      originLocations: originLocations,
      useOriginGeneration: useOriginGeneration,
      utcNow: utcNow,
      localNow: localNow,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
    );
    return (
      candidate: rebasedCandidate,
      baseline: scopedBaseline,
      ackGeneration: effectiveAckGeneration,
    );
  }

  /// Returns `true` when [storedBaseline] diverged from [originTasks], [originLabels], or [originLocations] via additions, deletions, or payload/timestamp edits.
  static bool _didBaselineAdvancePastOrigin(
    TaskBoard storedBaseline,
    Map<String, TaskItem> originTasks,
    Map<String, TdfLabel> originLabels,
    Map<String, TdfLocation> originLocations,
    DateTime utcNow,
  ) =>
      _didBaselineTasksAdvance(storedBaseline, originTasks, utcNow) ||
      _didBaselineLabelsAdvance(storedBaseline, originLabels) ||
      _didBaselineLocationsAdvance(storedBaseline, originLocations);

  /// Returns `true` when [storedBaseline] added, deleted, or modified any label relative to [originLabels].
  static bool _didBaselineLabelsAdvance(
    TaskBoard storedBaseline,
    Map<String, TdfLabel> originLabels,
  ) {
    final storedIds = <String>{};
    for (final label in storedBaseline.labels) {
      storedIds.add(label.id);
      final origin = originLabels[label.id];
      if (origin == null ||
          origin.effectiveModifiedAt != label.effectiveModifiedAt ||
          TdfPayloadComparison.compareLabelPayloads(origin, label) != 0) {
        return true;
      }
    }
    for (final id in originLabels.keys) {
      if (!storedIds.contains(id) &&
          storedBaseline.deletedBlock.findLabelRecord(id) != null) {
        return true;
      }
    }
    return false;
  }

  /// Returns `true` when [storedBaseline] added, deleted, or modified any location relative to [originLocations].
  static bool _didBaselineLocationsAdvance(
    TaskBoard storedBaseline,
    Map<String, TdfLocation> originLocations,
  ) {
    final storedIds = <String>{};
    for (final location in storedBaseline.locations) {
      storedIds.add(location.id);
      final origin = originLocations[location.id];
      if (origin == null ||
          origin.effectiveModifiedAt != location.effectiveModifiedAt ||
          TdfPayloadComparison.compareLocationPayloads(origin, location) != 0) {
        return true;
      }
    }
    for (final id in originLocations.keys) {
      if (!storedIds.contains(id) &&
          storedBaseline.deletedBlock.findLocationRecord(id) != null) {
        return true;
      }
    }
    return false;
  }

  /// Returns `true` when [storedBaseline] added, deleted, or modified any task (modulo automatic open-task block cleanup at [utcNow]) relative to [originTasks].
  static bool _didBaselineTasksAdvance(
    TaskBoard storedBaseline,
    Map<String, TaskItem> originTasks,
    DateTime utcNow,
  ) {
    final storedTasksById = <String, TaskItem>{
      for (final item in storedBaseline.allTasks) item.id: item,
    };
    final storedDeletedTaskIds = <String>{
      for (final record in storedBaseline.deletedBlock.tasks) record.taskId,
    };
    for (final item in storedBaseline.allTasks) {
      final origin = originTasks[item.id];
      if (origin == null ||
          !_isTaskUnchangedModuloBlockCleanup(
            originTask: origin,
            candidateTask: item,
            liveTasksById: storedTasksById,
            deletedTaskIds: storedDeletedTaskIds,
            utcNow: utcNow,
          )) {
        return true;
      }
    }
    for (final id in originTasks.keys) {
      if (!storedTasksById.containsKey(id) &&
          storedBaseline.deletedBlock.findTaskRecord(id) != null) {
        return true;
      }
    }
    return false;
  }

  /// Returns `true` when [candidate] modified or newly referenced any retired entity from [originTasks], [originLabels], or [originLocations].
  static bool _didCandidateModifyRetiredEntities(
    TaskBoard candidate, {
    required Map<String, TaskItem> originTasks,
    required Map<String, TdfLabel> originLabels,
    required Map<String, TdfLocation> originLocations,
    required Map<String, TaskItem> candidateTasksById,
    required Set<String> candidateDeletedTaskIds,
    required Set<String> retiredTaskIds,
    required Set<String> retiredLabelIds,
    required Set<String> retiredLocationIds,
    required DateTime utcNow,
  }) =>
      _didCandidateModifyRetiredTasks(
        candidate,
        originTasks,
        candidateTasksById,
        candidateDeletedTaskIds,
        retiredTaskIds,
        utcNow,
      ) ||
      _didCandidateModifyRetiredLabels(
        candidate,
        originTasks,
        originLabels,
        candidateTasksById,
        candidateDeletedTaskIds,
        retiredLabelIds,
        utcNow,
      ) ||
      _didCandidateModifyRetiredLocations(
        candidate,
        originTasks,
        originLabels,
        originLocations,
        candidateTasksById,
        candidateDeletedTaskIds,
        retiredLocationIds,
        utcNow,
      );

  /// Returns `true` when [candidate] modified a label in [retiredLabelIds] or modified a task that references [retiredLabelIds].
  static bool _didCandidateModifyRetiredLabels(
    TaskBoard candidate,
    Map<String, TaskItem> originTasks,
    Map<String, TdfLabel> originLabels,
    Map<String, TaskItem> candidateTasksById,
    Set<String> candidateDeletedTaskIds,
    Set<String> retiredLabelIds,
    DateTime utcNow,
  ) {
    if (retiredLabelIds.isEmpty) {
      return false;
    }
    for (final label in candidate.labels) {
      if (!retiredLabelIds.contains(label.id)) continue;
      final origin = originLabels[label.id];
      if (origin == null ||
          origin.effectiveModifiedAt != label.effectiveModifiedAt ||
          TdfPayloadComparison.compareLabelPayloads(origin, label) != 0) {
        return true;
      }
    }
    for (final item in candidate.allTasks) {
      if (!_hasAnyId(item.labelIds, retiredLabelIds)) continue;
      final origin = originTasks[item.id];
      if (origin == null ||
          !_isTaskUnchangedModuloBlockCleanup(
            originTask: origin,
            candidateTask: item,
            liveTasksById: candidateTasksById,
            deletedTaskIds: candidateDeletedTaskIds,
            utcNow: utcNow,
          )) {
        return true;
      }
    }
    return false;
  }

  /// Returns `true` when [candidate] modified a location in [retiredLocationIds] or modified a task or label referencing [retiredLocationIds].
  static bool _didCandidateModifyRetiredLocations(
    TaskBoard candidate,
    Map<String, TaskItem> originTasks,
    Map<String, TdfLabel> originLabels,
    Map<String, TdfLocation> originLocations,
    Map<String, TaskItem> candidateTasksById,
    Set<String> candidateDeletedTaskIds,
    Set<String> retiredLocationIds,
    DateTime utcNow,
  ) {
    if (retiredLocationIds.isEmpty) {
      return false;
    }
    for (final location in candidate.locations) {
      if (!retiredLocationIds.contains(location.id)) continue;
      final origin = originLocations[location.id];
      if (origin == null ||
          origin.effectiveModifiedAt != location.effectiveModifiedAt ||
          TdfPayloadComparison.compareLocationPayloads(origin, location) != 0) {
        return true;
      }
    }
    for (final label in candidate.labels) {
      final locationIds = TdfMetadata.collectDistinctLocationIds(
        label.conditions,
      );
      if (!_hasAnyId(locationIds, retiredLocationIds)) continue;
      final origin = originLabels[label.id];
      if (origin == null ||
          origin.effectiveModifiedAt != label.effectiveModifiedAt ||
          TdfPayloadComparison.compareLabelPayloads(origin, label) != 0) {
        return true;
      }
    }
    for (final item in candidate.allTasks) {
      final locationIds = TdfMetadata.collectDistinctLocationIds(
        item.conditions,
      );
      if (!_hasAnyId(locationIds, retiredLocationIds)) continue;
      final origin = originTasks[item.id];
      if (origin == null ||
          !_isTaskUnchangedModuloBlockCleanup(
            originTask: origin,
            candidateTask: item,
            liveTasksById: candidateTasksById,
            deletedTaskIds: candidateDeletedTaskIds,
            utcNow: utcNow,
          )) {
        return true;
      }
    }
    return false;
  }

  /// Returns `true` when [candidate] modified any task in [retiredTaskIds] (ignoring automatic open-task block cleanup at [utcNow]).
  static bool _didCandidateModifyRetiredTasks(
    TaskBoard candidate,
    Map<String, TaskItem> originTasks,
    Map<String, TaskItem> candidateTasksById,
    Set<String> candidateDeletedTaskIds,
    Set<String> retiredTaskIds,
    DateTime utcNow,
  ) {
    if (retiredTaskIds.isEmpty) {
      return false;
    }
    for (final item in candidate.allTasks) {
      if (!retiredTaskIds.contains(item.id)) continue;
      final origin = originTasks[item.id];
      if (origin == null ||
          !_isTaskUnchangedModuloBlockCleanup(
            originTask: origin,
            candidateTask: item,
            liveTasksById: candidateTasksById,
            deletedTaskIds: candidateDeletedTaskIds,
            utcNow: utcNow,
          )) {
        return true;
      }
    }
    return false;
  }

  /// Retains baseline labels known to [originLabels] (including tombstoned or retired labels when requested), preferring pre-reconcile [originLabels] revisions unless [baselineLabels] predates [originLabels].
  static List<TdfLabel> _filterBaselineLabels(
    List<TdfLabel> baselineLabels,
    Map<String, TdfLabel> originLabels,
    TdfDeletedBlock storedDeleted, {
    bool includeRetired = false,
  }) {
    final result = <TdfLabel>[];
    final seenIds = <String>{};
    for (final label in baselineLabels) {
      seenIds.add(label.id);
      if (originLabels[label.id] case final origin?) {
        result.add(
          label.effectiveModifiedAt.isBefore(origin.effectiveModifiedAt)
              ? label
              : origin,
        );
      }
    }
    for (final origin in originLabels.values) {
      if (!seenIds.contains(origin.id) &&
          (includeRetired ||
              storedDeleted.findLabelRecord(origin.id) != null)) {
        result.add(origin);
      }
    }
    return result;
  }

  /// Retains baseline locations known to [originLocations] (including tombstoned or retired locations when requested), preferring pre-reconcile [originLocations] revisions unless [baselineLocations] predates [originLocations].
  static List<TdfLocation> _filterBaselineLocations(
    List<TdfLocation> baselineLocations,
    Map<String, TdfLocation> originLocations,
    TdfDeletedBlock storedDeleted, {
    bool includeRetired = false,
  }) {
    final result = <TdfLocation>[];
    final seenIds = <String>{};
    for (final location in baselineLocations) {
      seenIds.add(location.id);
      if (originLocations[location.id] case final origin?) {
        result.add(
          location.effectiveModifiedAt.isBefore(origin.effectiveModifiedAt)
              ? location
              : origin,
        );
      }
    }
    for (final origin in originLocations.values) {
      if (!seenIds.contains(origin.id) &&
          (includeRetired ||
              storedDeleted.findLocationRecord(origin.id) != null)) {
        result.add(origin);
      }
    }
    return result;
  }

  /// Retains baseline tasks known to [originTasks] (including tombstoned or retired tasks when requested), preferring pre-reconcile [originTasks] revisions unless [baselineTasks] predates [originTasks] or differs only by automatic block cleanup.
  static List<TaskItem> _filterBaselineTasks(
    Iterable<TaskItem> baselineTasks,
    Map<String, TaskItem> originTasks,
    TdfDeletedBlock storedDeleted, {
    required Map<String, TaskItem> storedTasksById,
    required Set<String> storedDeletedTaskIds,
    required DateTime utcNow,
    bool includeRetired = false,
  }) {
    final result = <TaskItem>[];
    final seenIds = <String>{};
    for (final item in baselineTasks) {
      seenIds.add(item.id);
      if (originTasks[item.id] case final origin?) {
        final keepBaselineItem =
            item.effectiveModifiedAt.isBefore(origin.effectiveModifiedAt) ||
            _isTaskUnchangedModuloBlockCleanup(
              originTask: origin,
              candidateTask: item,
              liveTasksById: storedTasksById,
              deletedTaskIds: storedDeletedTaskIds,
              utcNow: utcNow,
            );
        result.add(keepBaselineItem ? item : origin);
      }
    }
    for (final origin in originTasks.values) {
      if (!seenIds.contains(origin.id) &&
          (includeRetired || storedDeleted.findTaskRecord(origin.id) != null)) {
        result.add(origin);
      }
    }
    return result;
  }

  /// Returns `true` when any identifier in [ids] is contained in [targetSet].
  static bool _hasAnyId(Iterable<String> ids, Set<String> targetSet) {
    for (final id in ids) {
      if (targetSet.contains(id)) {
        return true;
      }
    }
    return false;
  }

  /// Returns `true` when any dependency in [dependencies] targets an identifier in [retiredTaskIds].
  static bool _hasAnyRetiredDependency(
    List<TdfTaskDependency> dependencies,
    Set<String> retiredTaskIds,
  ) {
    for (final dependency in dependencies) {
      if (retiredTaskIds.contains(dependency.taskId)) {
        return true;
      }
    }
    return false;
  }

  /// Returns `true` when [candidateTask] and [originTask] represent the same task snapshot modulo automatic open-task block-reason cleanup at [utcNow].
  static bool _isTaskUnchangedModuloBlockCleanup({
    required TaskItem originTask,
    required TaskItem candidateTask,
    required Map<String, TaskItem> liveTasksById,
    required Set<String> deletedTaskIds,
    required DateTime utcNow,
  }) {
    if (originTask == candidateTask) {
      return true;
    }
    if (originTask.completions != candidateTask.completions ||
        originTask.isCompleted != candidateTask.isCompleted ||
        (originTask.completedAt != null) !=
            (candidateTask.completedAt != null)) {
      return false;
    }
    if (TdfPayloadComparison.taskPayloadsEqual(originTask, candidateTask)) {
      return originTask.effectiveModifiedAt ==
          candidateTask.effectiveModifiedAt;
    }
    if (originTask.isCompleted || originTask.completedAt != null) {
      return false;
    }
    return TdfPayloadComparison.taskPayloadsEqualModuloBlockCleanup(
      left: originTask,
      right: candidateTask,
      liveTasksById: liveTasksById,
      deletedTaskIds: deletedTaskIds,
      nowUtc: utcNow,
    );
  }

  /// Rebases [candidate] onto [targetGeneration] after stripping untouched entities and `blocked` references retired by an already-acknowledged generation bump.
  static TaskBoard _rebaseCandidateToGeneration(
    TaskBoard candidate, {
    required int targetGeneration,
    required Set<String> retiredTaskIds,
    required Set<String> retiredLabelIds,
    required Set<String> retiredLocationIds,
    required DateTime utcNow,
    required DateTime localNow,
    required TdfTimeZoneContext timeZone,
    required Duration? dueLeadWindow,
  }) {
    final nextTasks = retiredTaskIds.isEmpty
        ? candidate.allTasks
        : <TaskItem>[
            for (final item in candidate.allTasks)
              if (!retiredTaskIds.contains(item.id))
                _stripRetiredTaskDependencies(item, retiredTaskIds, utcNow),
          ];
    final nextLabels = retiredLabelIds.isEmpty
        ? candidate.labels
        : <TdfLabel>[
            for (final label in candidate.labels)
              if (!retiredLabelIds.contains(label.id)) label,
          ];
    final nextLocations = retiredLocationIds.isEmpty
        ? candidate.locations
        : <TdfLocation>[
            for (final location in candidate.locations)
              if (!retiredLocationIds.contains(location.id)) location,
          ];
    final nextQueue = retiredTaskIds.isEmpty
        ? candidate.queueBlock
        : TdfQueueBlock(
            modifiedAt: candidate.queueBlock.modifiedAt,
            taskIds: <String>[
              for (final id in candidate.queueBlock.taskIds)
                if (!retiredTaskIds.contains(id)) id,
            ],
          );
    return TaskBoard.evaluate(
      tasks: nextTasks,
      labels: nextLabels,
      locations: nextLocations,
      deletedBlock: TdfDeletedBlock(
        generation: targetGeneration,
        tasks: candidate.deletedBlock.tasks,
        labels: candidate.deletedBlock.labels,
        locations: candidate.deletedBlock.locations,
      ),
      queueBlock: nextQueue,
      evaluationTime: utcNow,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
    );
  }

  /// Restores pre-cleanup snapshots from [storedBaseline] or [originTasks] for open tasks in [candidate] whose only change was automatic block-reason cleanup.
  static TaskBoard _restorePreCleanupBystanderTasks({
    required TaskBoard candidate,
    required TaskBoard candidateOriginBoard,
    required TaskBoard? storedBaseline,
    required Map<String, TaskItem> originTasks,
    required Map<String, TaskItem> candidateTasksById,
    required Set<String> candidateDeletedTaskIds,
    required DateTime utcNow,
    required DateTime localNow,
    required TdfTimeZoneContext timeZone,
    required Duration? dueLeadWindow,
  }) {
    final originQueuedIds = candidateOriginBoard.queueBlock.taskIds.toSet();
    final candidateQueuedIds = candidate.queueBlock.taskIds.toSet();
    final storedTasksById = storedBaseline == null
        ? const <String, TaskItem>{}
        : <String, TaskItem>{
            for (final item in storedBaseline.allTasks) item.id: item,
          };
    final storedDeletedTaskIds = storedBaseline == null
        ? const <String>{}
        : <String>{
            for (final record in storedBaseline.deletedBlock.tasks)
              record.taskId,
          };
    var didRestoreAny = false;
    final nextTasks = <TaskItem>[];
    for (final item in candidate.allTasks) {
      final restored = _selectRestoredBystanderTask(
        item: item,
        originTask: originTasks[item.id],
        storedTask: storedTasksById[item.id],
        sameQueueMembership:
            originQueuedIds.contains(item.id) ==
            candidateQueuedIds.contains(item.id),
        candidateTasksById: candidateTasksById,
        candidateDeletedTaskIds: candidateDeletedTaskIds,
        storedTasksById: storedTasksById,
        storedDeletedTaskIds: storedDeletedTaskIds,
        utcNow: utcNow,
      );
      if (!identical(restored, item)) {
        didRestoreAny = true;
      }
      nextTasks.add(restored);
    }
    if (!didRestoreAny) {
      return candidate;
    }
    return TaskBoard.evaluate(
      tasks: nextTasks,
      labels: candidate.labels,
      locations: candidate.locations,
      deletedBlock: candidate.deletedBlock,
      queueBlock: candidate.queueBlock,
      evaluationTime: utcNow,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
    );
  }

  /// Scopes [storedBaseline] to [originTasks], [originLabels], and [originLocations] for a queued optimistic mutation.
  static TaskBoard _scopeBaselineToCandidateOrigin(
    TaskBoard storedBaseline,
    TaskBoard candidateOriginBoard, {
    required Map<String, TaskItem> originTasks,
    required Map<String, TdfLabel> originLabels,
    required Map<String, TdfLocation> originLocations,
    required bool useOriginGeneration,
    required DateTime utcNow,
    required DateTime localNow,
    required TdfTimeZoneContext timeZone,
    required Duration? dueLeadWindow,
  }) {
    final queueAdvanced =
        !storedBaseline.queueBlock.modifiedAt.isBefore(
          candidateOriginBoard.queueBlock.modifiedAt,
        ) &&
        TdfPayloadComparison.compareQueueBlocks(
              candidateOriginBoard.queueBlock,
              storedBaseline.queueBlock,
            ) !=
            0;
    if (!useOriginGeneration &&
        !queueAdvanced &&
        !_didBaselineAdvancePastOrigin(
          storedBaseline,
          originTasks,
          originLabels,
          originLocations,
          utcNow,
        )) {
      return storedBaseline;
    }
    final storedDeleted = storedBaseline.deletedBlock;
    final storedTasksById = <String, TaskItem>{
      for (final item in storedBaseline.allTasks) item.id: item,
    };
    final storedDeletedTaskIds = <String>{
      for (final record in storedDeleted.tasks) record.taskId,
    };
    return TaskBoard.evaluate(
      tasks: _filterBaselineTasks(
        storedBaseline.allTasks,
        originTasks,
        storedDeleted,
        storedTasksById: storedTasksById,
        storedDeletedTaskIds: storedDeletedTaskIds,
        utcNow: utcNow,
        includeRetired: useOriginGeneration,
      ),
      labels: _filterBaselineLabels(
        storedBaseline.labels,
        originLabels,
        storedDeleted,
        includeRetired: useOriginGeneration,
      ),
      locations: _filterBaselineLocations(
        storedBaseline.locations,
        originLocations,
        storedDeleted,
        includeRetired: useOriginGeneration,
      ),
      deletedBlock: useOriginGeneration
          ? candidateOriginBoard.deletedBlock
          : storedDeleted,
      queueBlock: queueAdvanced
          ? candidateOriginBoard.queueBlock
          : storedBaseline.queueBlock,
      evaluationTime: utcNow,
      localEvaluationTime: localNow,
      timeZone: timeZone,
      dueLeadWindow: dueLeadWindow,
    );
  }

  /// Selects the pre-cleanup snapshot for an untouched open bystander [item], or returns [item] when user-modified.
  static TaskItem _selectRestoredBystanderTask({
    required TaskItem item,
    required TaskItem? originTask,
    required TaskItem? storedTask,
    required bool sameQueueMembership,
    required Map<String, TaskItem> candidateTasksById,
    required Set<String> candidateDeletedTaskIds,
    required Map<String, TaskItem> storedTasksById,
    required Set<String> storedDeletedTaskIds,
    required DateTime utcNow,
  }) {
    if (originTask == null || !sameQueueMembership || item == originTask) {
      return item;
    }
    if (!_isTaskUnchangedModuloBlockCleanup(
      originTask: originTask,
      candidateTask: item,
      liveTasksById: candidateTasksById,
      deletedTaskIds: candidateDeletedTaskIds,
      utcNow: utcNow,
    )) {
      return item;
    }
    if (storedTask != null &&
        _isTaskUnchangedModuloBlockCleanup(
          originTask: originTask,
          candidateTask: storedTask,
          liveTasksById: storedTasksById,
          deletedTaskIds: storedDeletedTaskIds,
          utcNow: utcNow,
        )) {
      return storedTask;
    }
    return originTask;
  }

  /// Strips `blocked` references targeting [retiredTaskIds] from surviving open [item] and advances `modifiedAt` when changed.
  static TaskItem _stripRetiredTaskDependencies(
    TaskItem item,
    Set<String> retiredTaskIds,
    DateTime utcNow,
  ) {
    if (item.isCompleted ||
        item.completedAt != null ||
        item.dependencies.isEmpty ||
        !_hasAnyRetiredDependency(item.dependencies, retiredTaskIds)) {
      return item;
    }
    final remainingDependencies = <TdfTaskDependency>[
      for (final dependency in item.dependencies)
        if (!retiredTaskIds.contains(dependency.taskId)) dependency,
    ];
    final nextModifiedAt = utcNow.isAfter(item.effectiveModifiedAt)
        ? utcNow
        : item.effectiveModifiedAt;
    return item.copyWith(
      blockedByTaskIds: <String>[
        for (final dependency in remainingDependencies) dependency.taskId,
      ],
      dependencies: remainingDependencies,
      modifiedAt: nextModifiedAt,
    );
  }
}
