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
import 'tdf_error.dart';
import 'tdf_metadata.dart';
import 'tdf_payload_comparison.dart';
import 'tdf_sync_metadata.dart';
import 'tdf_timezone.dart';

/// Result of reconciling `label` blocks and label deletion records.
@immutable
class LabelReconciliationOutcome {
  /// Creates a [LabelReconciliationOutcome].
  const LabelReconciliationOutcome({
    required this.liveLabels,
    required this.deletedLabelsById,
    required this.conflictedIds,
    required this.ambiguousIds,
    required this.retiredByUndelete,
  });

  /// Label IDs requiring user recovery after deletion history expiry.
  final List<String> ambiguousIds;

  /// Label IDs with unresolved deletion vs. modification conflicts.
  final List<String> conflictedIds;

  /// Active label deletion records keyed by label ID.
  final Map<String, TdfDeletedLabelRecord> deletedLabelsById;

  /// Surviving reconciled live labels.
  final List<TdfLabel> liveLabels;

  /// Whether at least one deletion record was retired by an explicit undelete resolution.
  final bool retiredByUndelete;
}

/// Stateless per-entity three-way task and label reconciliation engine for `TaskBoardSync`.
@immutable
class TaskBoardReconciler {
  const TaskBoardReconciler._();

  /// Throws a [TdfSyncOutcomeException] when [labels] or [tasks] recorded deletion conflicts or ambiguous recovery items.
  static void checkSyncOutcomes(
    LabelReconciliationOutcome labels,
    TaskReconciliationOutcome tasks,
  ) {
    if (tasks.conflictedIds.isNotEmpty || labels.conflictedIds.isNotEmpty) {
      throw TdfSyncOutcomeException(
        kind: TdfSyncOutcomeKind.deletionConflict,
        conflictedTaskIds: List<String>.unmodifiable(tasks.conflictedIds),
        conflictedLabelIds: List<String>.unmodifiable(labels.conflictedIds),
        message: 'Entity deletion conflicts with concurrent live modification.',
      );
    }
    if (tasks.ambiguousIds.isNotEmpty || labels.ambiguousIds.isNotEmpty) {
      throw TdfSyncOutcomeException(
        kind: TdfSyncOutcomeKind.recoveryRequired,
        ambiguousTaskIds: List<String>.unmodifiable(tasks.ambiguousIds),
        ambiguousLabelIds: List<String>.unmodifiable(labels.ambiguousIds),
        message: 'Ambiguous local entities require user recovery after deletion history expiry.',
      );
    }
  }

  /// Reconciles all `label` blocks across [boards], [initialDeleted], [resolutions], and [options].
  static LabelReconciliationOutcome reconcileLabels(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    Map<String, TdfDeletedLabelRecord> initialDeleted,
    Map<String, TdfDeletionResolution> resolutions,
    (int?, bool, DateTime) options,
  ) {
    final (primary, secondary, baseline) = boards;
    final primaryMap = _indexById(primary.labels, (label) => label.id);
    final secondaryMap = _indexById(secondary.labels, (label) => label.id);
    final baselineMap = baseline != null
        ? _indexById(baseline.labels, (label) => label.id)
        : null;
    final context = _reconcileContext(boards, resolutions, options);
    final accumulator = (
      live: <TdfLabel>[],
      deleted: <String, TdfDeletedLabelRecord>{...initialDeleted},
      conflicted: <String>[],
      ambiguous: <String>[],
    );
    var retired = false;
    for (final id in <String>{...primaryMap.keys, ...secondaryMap.keys}) {
      final pair = (primaryMap[id], secondaryMap[id], baselineMap?[id]);
      if (_reconcileSingleLabel(id, pair, context, accumulator)) retired = true;
    }
    return LabelReconciliationOutcome(
      liveLabels: accumulator.live,
      deletedLabelsById: accumulator.deleted,
      conflictedIds: accumulator.conflicted,
      ambiguousIds: accumulator.ambiguous,
      retiredByUndelete: retired,
    );
  }

  /// Reconciles all `task` blocks across [boards], [initialDeleted], [resolutions], and [options].
  static TaskReconciliationOutcome reconcileTasks(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    Map<String, TdfDeletedTaskRecord> initialDeleted,
    Map<String, TdfDeletionResolution> resolutions,
    (int?, bool, DateTime) options,
  ) {
    final (primary, secondary, baseline) = boards;
    final primaryMap = _indexById(primary.allTasks, (task) => task.id);
    final secondaryMap = _indexById(secondary.allTasks, (task) => task.id);
    final baselineMap = baseline != null
        ? _indexById(baseline.allTasks, (task) => task.id)
        : null;
    final context = _reconcileContext(boards, resolutions, options);
    final accumulator = (
      live: <TaskItem>[],
      deleted: <String, TdfDeletedTaskRecord>{...initialDeleted},
      conflicted: <String>[],
      ambiguous: <String>[],
    );
    var retired = false;
    for (final id in <String>{...primaryMap.keys, ...secondaryMap.keys}) {
      final pair = (primaryMap[id], secondaryMap[id], baselineMap?[id]);
      if (_reconcileSingleTask(id, pair, context, accumulator)) retired = true;
    }
    return TaskReconciliationOutcome(
      liveTasks: accumulator.live,
      deletedTasksById: accumulator.deleted,
      conflictedIds: accumulator.conflicted,
      ambiguousIds: accumulator.ambiguous,
      retiredByUndelete: retired,
    );
  }

  /// Strips deleted labels from [tasks] (advancing affected tasks' `modified` timestamp)
  /// and validates that no unknown label references remain per Sections 6.7.7 and 6.8.1.
  static List<TaskItem> stripDeletedLabelsAndValidateReferences(
    List<TaskItem> tasks,
    Set<String> validIds,
    Map<String, TdfDeletedLabelRecord> deletedById,
    List<TdfLabel>? baselineLabels,
  ) {
    final baseIds = <String>{
      if (baselineLabels != null)
        for (final label in baselineLabels) label.id,
    };
    return <TaskItem>[
      for (final task in tasks)
        _stripDeletedLabelsFromSingleTask(task, validIds, deletedById, baseIds),
    ];
  }

  /// Verifies that deletion history generations have not rolled back and task completion counters have not regressed.
  static void verifyGenerationsAndCompletionHistory(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    int? effectiveAckGen,
  ) {
    final (primary, secondary, baseline) = boards;
    final leftGen = primary.deletedBlock.generation;
    final rightGen = secondary.deletedBlock.generation;
    if (effectiveAckGen != null &&
        (leftGen < effectiveAckGen || rightGen < effectiveAckGen)) {
      throw const TdfSyncOutcomeException(
        kind: TdfSyncOutcomeKind.syncGenerationRollback,
        message: 'Shared deletion history generation is lower than the acknowledged generation.',
      );
    }
    if (baseline == null) return;
    final primaryMap = _indexById(primary.allTasks, (task) => task.id);
    final secondaryMap = _indexById(secondary.allTasks, (task) => task.id);
    final regressedIds = <String>[];
    for (final baseTask in baseline.allTasks) {
      final primaryTask = primaryMap[baseTask.id];
      final secondaryTask = secondaryMap[baseTask.id];
      if ((primaryTask != null &&
              primaryTask.completions < baseTask.completions) ||
          (secondaryTask != null &&
              secondaryTask.completions < baseTask.completions)) {
        regressedIds.add(baseTask.id);
      }
    }
    if (regressedIds.isNotEmpty) {
      throw TdfSyncOutcomeException(
        kind: TdfSyncOutcomeKind.recoveryRequired,
        ambiguousTaskIds: List<String>.unmodifiable(regressedIds),
        message: 'Task completion counter regressed below the proven baseline counter.',
      );
    }
  }

  /// Computes `decisionRevision = max(now, eachObservedRevision + 1 second)` per Section 6.8.2.
  static DateTime _computeDecisionRevision(
    (DateTime, DateTime, DateTime?) revisions,
    DateTime now,
  ) {
    final (liveRev, deletedRev, baseRev) = revisions;
    var maxObserved = liveRev.isAfter(deletedRev) ? liveRev : deletedRev;
    if (baseRev != null && baseRev.isAfter(maxObserved)) maxObserved = baseRev;
    final bumped = maxObserved.add(const Duration(seconds: 1));
    final decision = now.isAfter(bumped) ? now : bumped;
    if (!TdfCalendar.isWithinTimestampBounds(decision)) {
      throw const TdfException(
        kind: TdfErrorKind.invalidTimestamp,
        line: 1,
        message: 'Decision revision exceeds maximum supported timestamp.',
      );
    }
    return decision;
  }

  /// Indexes [items] by the key returned from [idOf].
  static Map<String, T> _indexById<T>(
    Iterable<T> items,
    String Function(T) idOf,
  ) => <String, T>{for (final item in items) idOf(item): item};

  /// Returns whether [label] is identical to [baseLabel] in payload and effective revision.
  static bool _isLabelUnchangedFromBaseline(
    TdfLabel label,
    TdfLabel baseLabel,
  ) =>
      label.effectiveModifiedAt == baseLabel.effectiveModifiedAt &&
      TdfPayloadComparison.compareLabelPayloads(label, baseLabel) == 0;

  /// Returns whether [task] is identical to [baseTask] in payload, completions, and effective revision.
  static bool _isTaskUnchangedFromBaseline(TaskItem task, TaskItem baseTask) =>
      task.completions == baseTask.completions &&
      task.effectiveModifiedAt == baseTask.effectiveModifiedAt &&
      TdfPayloadComparison.compareTaskPayloads(task, baseTask) == 0;

  /// Returns the maximum of three integers.
  static int _max3Int(int a, int b, int c) {
    final ab = a >= b ? a : b;
    return ab >= c ? ab : c;
  }

  /// Computes generation advancement and ambiguity flags for one-sided entities absent from baseline.
  static _ReconcileContext _reconcileContext(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    Map<String, TdfDeletionResolution> resolutions,
    (int?, bool, DateTime) options,
  ) {
    final (primary, secondary, baseline) = boards;
    final (ackGen, requireAck, now) = options;
    final leftGen = primary.deletedBlock.generation;
    final rightGen = secondary.deletedBlock.generation;
    final genAdvanced =
        leftGen != rightGen ||
        (ackGen != null && (leftGen > ackGen || rightGen > ackGen));
    final noBaseAmb = baseline == null && genAdvanced;
    return (
      genAdvanced: genAdvanced,
      primaryAmb:
          noBaseAmb ||
          rightGen > (ackGen ?? leftGen) ||
          (requireAck && ackGen == null),
      secondaryAmb: noBaseAmb || leftGen > (ackGen ?? rightGen),
      now: now,
      resolutions: resolutions,
    );
  }

  /// Reconciles a single label [id] and returns whether an explicit `Undelete` retired a deletion record.
  static bool _reconcileSingleLabel(
    String id,
    (TdfLabel?, TdfLabel?, TdfLabel?) entities,
    _ReconcileContext context,
    _LabelAccumulator accumulator,
  ) {
    final (primaryLabel, secondaryLabel, baselineLabel) = entities;
    if (primaryLabel != null && secondaryLabel != null) {
      accumulator.live.add(
        TdfPayloadComparison.mergeLabelWithBaseline(
          local: primaryLabel,
          incoming: secondaryLabel,
          baseline: baselineLabel,
        ),
      );
      return false;
    }

    final surviving = primaryLabel ?? secondaryLabel;
    if (surviving == null) return false;
    final unchanged =
        baselineLabel != null &&
        _isLabelUnchangedFromBaseline(surviving, baselineLabel);

    final TdfDeletedLabelRecord conflictRecord;
    if (accumulator.deleted[id] case final existingDeleted?) {
      if (unchanged) return false;
      conflictRecord = existingDeleted;
    } else if (baselineLabel != null) {
      if (context.genAdvanced) {
        if (!unchanged) accumulator.ambiguous.add(id);
        return false;
      }
      final synthAt = TaskItem.nextModifiedTimestamp(
        context.now,
        baselineLabel.effectiveModifiedAt,
      );
      conflictRecord = TdfDeletedLabelRecord(labelId: id, deletedAt: synthAt);
      if (unchanged) {
        accumulator.deleted[id] = conflictRecord;
        return false;
      }
    } else {
      if (primaryLabel != null ? context.primaryAmb : context.secondaryAmb) {
        accumulator.ambiguous.add(id);
      } else {
        accumulator.live.add(surviving);
      }
      return false;
    }
    final conflict = (surviving, baselineLabel, conflictRecord);
    return _resolveLabelDeletionConflict(conflict, context, accumulator);
  }

  /// Reconciles a single task [id] and returns whether an explicit `Undelete` retired a deletion record.
  static bool _reconcileSingleTask(
    String id,
    (TaskItem?, TaskItem?, TaskItem?) entities,
    _ReconcileContext context,
    _TaskAccumulator accumulator,
  ) {
    final (primaryTask, secondaryTask, baselineTask) = entities;
    if (primaryTask != null && secondaryTask != null) {
      accumulator.live.add(
        TdfPayloadComparison.mergeTaskWithBaseline(
          local: primaryTask,
          incoming: secondaryTask,
          baseline: baselineTask,
        ),
      );
      return false;
    }

    final surviving = primaryTask ?? secondaryTask;
    if (surviving == null) return false;
    final unchanged =
        baselineTask != null &&
        _isTaskUnchangedFromBaseline(surviving, baselineTask);

    final TdfDeletedTaskRecord conflictRecord;
    if (accumulator.deleted[id] case final existing?) {
      if (unchanged) {
        final maxComp = _max3Int(
          existing.completionsCheckpoint,
          surviving.completions,
          baselineTask.completions,
        );
        accumulator.deleted[id] = TdfDeletedTaskRecord(
          taskId: id,
          deletedAt: existing.deletedAt,
          completionsCheckpoint: maxComp,
        );
        return false;
      }
      conflictRecord = existing;
    } else if (baselineTask != null) {
      if (context.genAdvanced) {
        if (!unchanged) accumulator.ambiguous.add(id);
        return false;
      }
      final synthAt = TaskItem.nextModifiedTimestamp(
        context.now,
        baselineTask.effectiveModifiedAt,
      );
      conflictRecord = TdfDeletedTaskRecord(
        taskId: id,
        deletedAt: synthAt,
        completionsCheckpoint: baselineTask.completions,
      );
      if (unchanged) {
        accumulator.deleted[id] = conflictRecord;
        return false;
      }
    } else {
      if (primaryTask != null ? context.primaryAmb : context.secondaryAmb) {
        accumulator.ambiguous.add(id);
      } else {
        accumulator.live.add(surviving);
      }
      return false;
    }
    final conflict = (surviving, baselineTask, conflictRecord);
    return _resolveTaskDeletionConflict(conflict, context, accumulator);
  }

  /// Applies the conflict resolution (or records a `DeletionConflict`) for [conflict] per Section 6.8.2.
  static bool _resolveLabelDeletionConflict(
    (TdfLabel, TdfLabel?, TdfDeletedLabelRecord) conflict,
    _ReconcileContext context,
    _LabelAccumulator accumulator,
  ) {
    final (surviving, baselineLabel, deletedRecord) = conflict;
    final id = surviving.id;
    final resolution = context.resolutions[id];
    if (resolution == null) {
      accumulator.conflicted.add(id);
      return false;
    }
    final revisions = (
      surviving.effectiveModifiedAt,
      deletedRecord.deletedAt,
      baselineLabel?.effectiveModifiedAt,
    );
    final revision = _computeDecisionRevision(revisions, context.now);
    switch (resolution) {
      case TdfDeletionResolution.delete:
        accumulator.deleted[id] = TdfDeletedLabelRecord(
          labelId: id,
          deletedAt: revision,
        );
        return false;
      case TdfDeletionResolution.undelete:
        accumulator.deleted.remove(id);
        accumulator.live.add(surviving.copyWith(modifiedAt: revision));
        return true;
    }
  }

  /// Applies the conflict resolution (or records a `DeletionConflict`) for [conflict] per Section 6.8.2.
  static bool _resolveTaskDeletionConflict(
    (TaskItem, TaskItem?, TdfDeletedTaskRecord) conflict,
    _ReconcileContext context,
    _TaskAccumulator accumulator,
  ) {
    final (surviving, baselineTask, deletedRecord) = conflict;
    final id = surviving.id;
    final resolution = context.resolutions[id];
    if (resolution == null) {
      accumulator.conflicted.add(id);
      return false;
    }
    final revisions = (
      surviving.effectiveModifiedAt,
      deletedRecord.deletedAt,
      baselineTask?.effectiveModifiedAt,
    );
    final revision = _computeDecisionRevision(revisions, context.now);
    final maxComp = _max3Int(
      surviving.completions,
      baselineTask?.completions ?? 0,
      deletedRecord.completionsCheckpoint,
    );
    switch (resolution) {
      case TdfDeletionResolution.delete:
        accumulator.deleted[id] = TdfDeletedTaskRecord(
          taskId: id,
          deletedAt: revision,
          completionsCheckpoint: maxComp,
        );
        return false;
      case TdfDeletionResolution.undelete:
        accumulator.deleted.remove(id);
        accumulator.live.add(
          surviving.copyWith(completions: maxComp, modifiedAt: revision),
        );
        return true;
    }
  }

  /// Strips deleted labels from a single [task] and validates remaining label references.
  static TaskItem _stripDeletedLabelsFromSingleTask(
    TaskItem task,
    Set<String> validLabelIds,
    Map<String, TdfDeletedLabelRecord> deletedLabelsById,
    Set<String> baselineLabelSet,
  ) {
    if (task.labelIds.isEmpty) return task;
    final retained = <String>[];
    DateTime? latestLabelDeletion;
    var strippedAny = false;

    for (final labelId in task.labelIds) {
      if (validLabelIds.contains(labelId)) {
        retained.add(labelId);
        continue;
      }
      final deletedRecord = deletedLabelsById[labelId];
      if (deletedRecord != null || baselineLabelSet.contains(labelId)) {
        strippedAny = true;
        if (deletedRecord != null &&
            (latestLabelDeletion == null ||
                deletedRecord.deletedAt.isAfter(latestLabelDeletion))) {
          latestLabelDeletion = deletedRecord.deletedAt;
        }
        continue;
      }
      throw TdfException(
        kind: TdfErrorKind.unknownLabelReference,
        line: 1,
        message:
            'Merged task "${task.id}" references undeclared label "$labelId".',
      );
    }

    if (!strippedAny) return task;
    var baseModified = task.effectiveModifiedAt;
    if (latestLabelDeletion != null &&
        latestLabelDeletion.isAfter(baseModified)) {
      baseModified = latestLabelDeletion;
    }
    return task.copyWith(
      labelIds: retained,
      modifiedAt: baseModified.add(const Duration(seconds: 1)),
    );
  }
}

/// Result of reconciling `task` blocks and task deletion records.
@immutable
class TaskReconciliationOutcome {
  /// Creates a [TaskReconciliationOutcome].
  const TaskReconciliationOutcome({
    required this.liveTasks,
    required this.deletedTasksById,
    required this.conflictedIds,
    required this.ambiguousIds,
    required this.retiredByUndelete,
  });

  /// Task IDs requiring user recovery after deletion history expiry or completion regression.
  final List<String> ambiguousIds;

  /// Task IDs with unresolved deletion vs. modification conflicts.
  final List<String> conflictedIds;

  /// Active task deletion records keyed by task ID.
  final Map<String, TdfDeletedTaskRecord> deletedTasksById;

  /// Surviving reconciled live tasks.
  final List<TaskItem> liveTasks;

  /// Whether at least one deletion record was retired by an explicit undelete resolution.
  final bool retiredByUndelete;
}

/// Mutable accumulator used while reconciling labels across two boards.
typedef _LabelAccumulator = ({
  List<TdfLabel> live,
  Map<String, TdfDeletedLabelRecord> deleted,
  List<String> conflicted,
  List<String> ambiguous,
});

/// Precomputed generation advancement and missing-baseline ambiguity context.
typedef _ReconcileContext = ({
  bool genAdvanced,
  bool primaryAmb,
  bool secondaryAmb,
  DateTime now,
  Map<String, TdfDeletionResolution> resolutions,
});

/// Mutable accumulator used while reconciling tasks across two boards.
typedef _TaskAccumulator = ({
  List<TaskItem> live,
  Map<String, TdfDeletedTaskRecord> deleted,
  List<String> conflicted,
  List<String> ambiguous,
});
