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

import 'dart:convert' show Utf8Codec;
import 'dart:typed_data' show BytesBuilder, Uint8List;

import 'package:flutter/foundation.dart';

import '../services/app_logger.dart';
import '../services/tdf_service.dart';
import 'task_board.dart';
import 'task_item.dart';
import 'tdf_metadata.dart';
import 'tdf_payload_comparison.dart';
import 'tdf_sync_metadata.dart';
import 'tdf_timezone.dart';

/// Stateless entity-level synchronization, three-way merge, deletion record
/// reconciliation, and shared queue merge engine for [TaskBoard] documents
/// per `TDF_SPEC.md` Sections 6.7, 6.8, 6.9.5, and 6.11.2.
@immutable
class TaskBoardSync {
  const TaskBoardSync._();

  /// Merges [primary] and [secondary] entity-by-entity (`label`, `task`, `deleted`,
  /// and `queue` blocks) using [baseline], [acknowledgedGeneration],
  /// [deletedLabelTimestamps], [taskConflictResolutions], and [labelConflictResolutions],
  /// and evaluates the 6-tier pipeline at [evaluationTime].
  static TaskBoard merge({
    required TaskBoard primary,
    required TaskBoard secondary,
    TaskBoard? baseline,
    int? acknowledgedGeneration,
    Map<String, DateTime> deletedLabelTimestamps = const {},
    Map<String, TdfDeletionResolution> taskConflictResolutions = const {},
    Map<String, TdfDeletionResolution> labelConflictResolutions = const {},
    required DateTime evaluationTime,
    DateTime? localEvaluationTime,
    bool pruneExpiredDeleted = true,
    bool requireAcknowledgedGeneration = false,
  }) {
    final now = TaskItem.normalizeTimestamp(evaluationTime);
    final effectiveAckGen =
        acknowledgedGeneration ?? baseline?.deletedBlock.generation;
    final lGen = primary.deletedBlock.generation;
    final rGen = secondary.deletedBlock.generation;

    _verifyGenerationsAndCompletionHistory(
      primary: primary,
      secondary: secondary,
      baseline: baseline,
      effectiveAckGen: effectiveAckGen,
    );

    final targetGeneration = lGen >= rGen ? lGen : rGen;
    final combinedDeleted = _combineInitialDeletedRecords(
      primary: primary.deletedBlock,
      secondary: secondary.deletedBlock,
      baseline: baseline?.deletedBlock,
      deletedLabelTimestamps: deletedLabelTimestamps,
    );

    final labelOutcome = _reconcileLabels(
      primaryLabels: primary.labels,
      secondaryLabels: secondary.labels,
      baselineLabels: baseline?.labels,
      initialDeletedLabels: combinedDeleted.labels,
      resolutions: labelConflictResolutions,
      lGen: lGen,
      rGen: rGen,
      effectiveAckGen: effectiveAckGen,
      requireAcknowledgedGeneration: requireAcknowledgedGeneration,
      now: now,
    );

    final taskOutcome = _reconcileTasks(
      primaryTasks: primary.allTasks,
      secondaryTasks: secondary.allTasks,
      baselineTasks: baseline?.allTasks,
      initialDeletedTasks: combinedDeleted.tasks,
      resolutions: taskConflictResolutions,
      lGen: lGen,
      rGen: rGen,
      effectiveAckGen: effectiveAckGen,
      requireAcknowledgedGeneration: requireAcknowledgedGeneration,
      now: now,
    );

    _checkSyncOutcomes(labelOutcome: labelOutcome, taskOutcome: taskOutcome);

    final validLabelIds = <String>{
      for (final label in labelOutcome.liveLabels) label.id,
    };
    final tasksAfterLabelStrip = _stripDeletedLabelsAndValidateReferences(
      tasks: taskOutcome.liveTasks,
      validLabelIds: validLabelIds,
      deletedLabelsById: labelOutcome.deletedLabelsById,
      baselineLabels: baseline?.labels,
    );

    _validateMergedGraphAndBounds(
      tasks: tasksAfterLabelStrip,
      labels: labelOutcome.liveLabels,
    );

    final finalizedDeletedBlock = _finalizeDeletedBlock(
      baseGeneration: targetGeneration,
      deletedTasks: taskOutcome.deletedTasksById.values,
      deletedLabels: labelOutcome.deletedLabelsById.values,
      retiredByUndelete:
          labelOutcome.retiredByUndelete || taskOutcome.retiredByUndelete,
      pruneExpiredDeleted: pruneExpiredDeleted,
      now: now,
    );

    final undeletedTaskIds = <String>{
      for (final entry in taskConflictResolutions.entries)
        if (entry.value == TdfDeletionResolution.undelete) entry.key,
    };
    final mergedQueueBlock = _mergeQueueBlocks(
      primaryQueue: primary.queueBlock,
      secondaryQueue: secondary.queueBlock,
      baselineQueue: baseline?.queueBlock,
      primaryTaskIds: <String>{for (final task in primary.allTasks) task.id},
      secondaryTaskIds: <String>{
        for (final task in secondary.allTasks) task.id,
      },
      undeletedTaskIds: undeletedTaskIds,
      mergedTasks: tasksAfterLabelStrip,
    );

    final mergedBoard = TaskBoard.evaluate(
      tasks: tasksAfterLabelStrip,
      evaluationTime: now,
      localEvaluationTime: localEvaluationTime,
      labels: labelOutcome.liveLabels,
      deletedBlock: finalizedDeletedBlock,
      queueBlock: mergedQueueBlock,
      pruneExpiredCompleted: true,
    );
    AppLogger.info(
      LogTag.sync,
      'TaskBoardSync.merge completed: primary=(tasks=${primary.allTasks.length}, labels=${primary.labels.length}, gen=$lGen), secondary=(tasks=${secondary.allTasks.length}, labels=${secondary.labels.length}, gen=$rGen) -> merged=(tasks=${mergedBoard.allTasks.length}, labels=${mergedBoard.labels.length}, gen=${mergedBoard.deletedBlock.generation})',
    );
    return mergedBoard;
  }

  /// Recovers ambiguous local entities identified by [recoverTaskIds] and [recoverLabelIds]
  /// from [localBoard] into [sharedBoard] as new entities with freshly generated 10-character
  /// Base62 IDs, rewriting `labels` and `blocked` references among recovered entities per
  /// `TDF_SPEC.md` Section 6.8.4.
  static TaskBoard recoverAmbiguousEntities({
    required TaskBoard localBoard,
    required TaskBoard sharedBoard,
    TaskBoard? baseline,
    Iterable<String> recoverTaskIds = const <String>[],
    Iterable<String> recoverLabelIds = const <String>[],
    required DateTime evaluationTime,
    DateTime? localEvaluationTime,
  }) {
    final now = TaskItem.normalizeTimestamp(evaluationTime);
    final recoverTaskSet = <String>{...recoverTaskIds};
    final recoverLabelSet = <String>{...recoverLabelIds};

    final reservedLabelIds = <String>{
      for (final label in localBoard.labels) label.id,
      for (final label in sharedBoard.labels) label.id,
      for (final record in localBoard.deletedBlock.labels) record.labelId,
      for (final record in sharedBoard.deletedBlock.labels) record.labelId,
    };
    final reservedTaskIds = <String>{
      for (final task in localBoard.allTasks) task.id,
      for (final task in sharedBoard.allTasks) task.id,
      for (final record in localBoard.deletedBlock.tasks) record.taskId,
      for (final record in sharedBoard.deletedBlock.tasks) record.taskId,
    };

    final labelIdMap = <String, String>{};
    for (final oldLabelId in recoverLabelSet) {
      final newId = generateLabelId(
        timestamp: now,
        existingIds: reservedLabelIds,
      );
      reservedLabelIds.add(newId);
      labelIdMap[oldLabelId] = newId;
    }

    final taskIdMap = <String, String>{};
    for (final oldTaskId in recoverTaskSet) {
      final newId = generateTaskId(
        timestamp: now,
        existingIds: reservedTaskIds,
      );
      reservedTaskIds.add(newId);
      taskIdMap[oldTaskId] = newId;
    }

    final sharedLabelIds = <String>{
      for (final label in sharedBoard.labels) label.id,
    };
    final sharedTaskIds = <String>{
      for (final task in sharedBoard.allTasks) task.id,
    };

    final adjustedLocalLabels = <TdfLabel>[];
    for (final label in localBoard.labels) {
      if (labelIdMap[label.id] case final newId?) {
        final nextMod = TaskItem.nextModifiedTimestamp(
          now,
          label.effectiveModifiedAt,
        );
        adjustedLocalLabels.add(
          TdfLabel(
            id: newId,
            name: label.name,
            color: label.color,
            note: label.note,
            modifiedAt: nextMod,
            conditions: label.conditions,
          ),
        );
      } else if (sharedLabelIds.contains(label.id)) {
        adjustedLocalLabels.add(label);
      }
    }

    final adjustedLocalTasks = <TaskItem>[];
    for (final task in localBoard.allTasks) {
      if (taskIdMap[task.id] case final newId?) {
        adjustedLocalTasks.add(
          _rewriteRecoveredTask(
            task: task,
            newId: newId,
            labelIdMap: labelIdMap,
            taskIdMap: taskIdMap,
            now: now,
          ),
        );
      } else if (sharedTaskIds.contains(task.id)) {
        adjustedLocalTasks.add(task);
      }
    }

    final adjustedQueueIds = <String>[
      for (final id in localBoard.queueBlock.taskIds)
        if (taskIdMap[id] case final mapped?)
          mapped
        else if (sharedTaskIds.contains(id))
          id,
    ];

    final preparedLocal = TaskBoard.evaluate(
      tasks: adjustedLocalTasks,
      labels: adjustedLocalLabels,
      deletedBlock: localBoard.deletedBlock.copyWith(
        generation: sharedBoard.deletedBlock.generation,
      ),
      queueBlock: localBoard.queueBlock.copyWith(taskIds: adjustedQueueIds),
      evaluationTime: now,
      localEvaluationTime: localEvaluationTime,
    );

    return merge(
      primary: preparedLocal,
      secondary: sharedBoard,
      baseline: baseline,
      acknowledgedGeneration: sharedBoard.deletedBlock.generation,
      evaluationTime: now,
      localEvaluationTime: localEvaluationTime,
    );
  }

  /// Evaluates the 6-tier pipeline on [board] at [evaluationTime] while preserving
  /// each entity's existing `modifiedAt` state (including omitted `modified` directives)
  /// per `TDF_SPEC.md` Section 6.7.1 and 6.7.4.
  static TaskBoard stampAndNormalize(
    TaskBoard board, {
    required DateTime evaluationTime,
    DateTime? localEvaluationTime,
  }) {
    final now = TaskItem.normalizeTimestamp(evaluationTime);
    return TaskBoard.evaluate(
      tasks: board.allTasks,
      evaluationTime: now,
      localEvaluationTime: localEvaluationTime,
      labels: board.labels,
      deletedBlock: board.deletedBlock,
      queueBlock: board.queueBlock,
      pruneExpiredCompleted: true,
    );
  }

  /// Throws a [TdfSyncOutcomeException] when [labelOutcome] or [taskOutcome] recorded deletion conflicts or ambiguous recovery items.
  static void _checkSyncOutcomes({
    required _LabelReconciliationOutcome labelOutcome,
    required _TaskReconciliationOutcome taskOutcome,
  }) {
    if (taskOutcome.conflictedIds.isNotEmpty ||
        labelOutcome.conflictedIds.isNotEmpty) {
      throw TdfSyncOutcomeException(
        kind: TdfSyncOutcomeKind.deletionConflict,
        conflictedTaskIds: List<String>.unmodifiable(taskOutcome.conflictedIds),
        conflictedLabelIds: List<String>.unmodifiable(
          labelOutcome.conflictedIds,
        ),
        message: 'Entity deletion conflicts with concurrent live modification.',
      );
    }
    if (taskOutcome.ambiguousIds.isNotEmpty ||
        labelOutcome.ambiguousIds.isNotEmpty) {
      throw TdfSyncOutcomeException(
        kind: TdfSyncOutcomeKind.recoveryRequired,
        ambiguousTaskIds: List<String>.unmodifiable(taskOutcome.ambiguousIds),
        ambiguousLabelIds: List<String>.unmodifiable(labelOutcome.ambiguousIds),
        message: 'Ambiguous local entities require user recovery after deletion history expiry.',
      );
    }
  }

  /// Collects all unique entity keys in declaration order across [first] and [second].
  static List<String> _collectOrderedKeys(
    Iterable<String> first,
    Iterable<String> second,
  ) {
    final seen = <String>{};
    final ordered = <String>[];
    for (final id in first) {
      if (seen.add(id)) {
        ordered.add(id);
      }
    }
    for (final id in second) {
      if (seen.add(id)) {
        ordered.add(id);
      }
    }
    return ordered;
  }

  /// Combines active deletion records from [primary] and [secondary], discarding old acknowledged records when one side advanced generation.
  static ({
    Map<String, TdfDeletedTaskRecord> tasks,
    Map<String, TdfDeletedLabelRecord> labels,
  })
  _combineInitialDeletedRecords({
    required TdfDeletedBlock primary,
    required TdfDeletedBlock secondary,
    required TdfDeletedBlock? baseline,
    required Map<String, DateTime> deletedLabelTimestamps,
  }) {
    final discardAckPrimary = primary.generation < secondary.generation;
    final discardAckSecondary = secondary.generation < primary.generation;

    final taskRecords = <String, TdfDeletedTaskRecord>{};
    for (final record in primary.tasks) {
      if (!_isAcknowledgedInBaselineTask(
        record,
        baseline,
        discard: discardAckPrimary,
      )) {
        taskRecords[record.taskId] = record;
      }
    }
    for (final record in secondary.tasks) {
      if (!_isAcknowledgedInBaselineTask(
        record,
        baseline,
        discard: discardAckSecondary,
      )) {
        final existing = taskRecords[record.taskId];
        taskRecords[record.taskId] = existing == null
            ? record
            : existing.mergeWith(record);
      }
    }

    final labelRecords = <String, TdfDeletedLabelRecord>{};
    for (final record in primary.labels) {
      if (!_isAcknowledgedInBaselineLabel(
        record,
        baseline,
        discard: discardAckPrimary,
      )) {
        labelRecords[record.labelId] = record;
      }
    }
    for (final record in secondary.labels) {
      if (!_isAcknowledgedInBaselineLabel(
        record,
        baseline,
        discard: discardAckSecondary,
      )) {
        final existing = labelRecords[record.labelId];
        if (existing == null || record.deletedAt.isAfter(existing.deletedAt)) {
          labelRecords[record.labelId] = record;
        }
      }
    }
    for (final entry in deletedLabelTimestamps.entries) {
      if (!isValidLabelId(entry.key)) {
        continue;
      }
      final normalizedTs = TaskItem.normalizeTimestamp(entry.value);
      final existing = labelRecords[entry.key];
      if (existing == null || normalizedTs.isAfter(existing.deletedAt)) {
        labelRecords[entry.key] = TdfDeletedLabelRecord(
          labelId: entry.key,
          deletedAt: normalizedTs,
        );
      }
    }
    return (tasks: taskRecords, labels: labelRecords);
  }

  /// Computes `decisionRevision = max(now, eachObservedRevision + 1 second)` per Section 6.8.2.
  static DateTime _computeDecisionRevision(
    DateTime now,
    DateTime liveRevision,
    DateTime deletedRevision,
    DateTime? baselineRevision,
  ) {
    var maxObserved = liveRevision.isAfter(deletedRevision)
        ? liveRevision
        : deletedRevision;
    if (baselineRevision != null && baselineRevision.isAfter(maxObserved)) {
      maxObserved = baselineRevision;
    }
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

  /// Prunes expired deletion records (> `2,592,000` seconds) and increments `generation` once when records are retired per Section 6.8.3.
  static TdfDeletedBlock _finalizeDeletedBlock({
    required int baseGeneration,
    required Iterable<TdfDeletedTaskRecord> deletedTasks,
    required Iterable<TdfDeletedLabelRecord> deletedLabels,
    required bool retiredByUndelete,
    required bool pruneExpiredDeleted,
    required DateTime now,
  }) {
    var anyExpired = false;
    final activeTasks = <TdfDeletedTaskRecord>[];
    for (final record in deletedTasks) {
      final isExpired =
          pruneExpiredDeleted &&
          now.difference(record.deletedAt).inSeconds >
              TaskBoard.completedRetentionSeconds;
      if (isExpired) {
        anyExpired = true;
      } else {
        activeTasks.add(record);
      }
    }

    final activeLabels = <TdfDeletedLabelRecord>[];
    for (final record in deletedLabels) {
      final isExpired =
          pruneExpiredDeleted &&
          now.difference(record.deletedAt).inSeconds >
              TaskBoard.completedRetentionSeconds;
      if (isExpired) {
        anyExpired = true;
      } else {
        activeLabels.add(record);
      }
    }

    if (activeTasks.length + activeLabels.length >
        TdfDeletedBlock.maxDeletedRecords) {
      throw const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message: 'Merged deleted block exceeds MAX_DELETED_RECORDS (4096).',
      );
    }

    var nextGeneration = baseGeneration;
    if (anyExpired || retiredByUndelete) {
      if (baseGeneration >= TdfDeletedBlock.maxGeneration) {
        throw const TdfException(
          kind: TdfErrorKind.limitExceeded,
          line: 1,
          message: 'Deletion history generation exceeds MAX_SYNC_GENERATION (9007199254740991).',
        );
      }
      nextGeneration = baseGeneration + 1;
    }

    return TdfDeletedBlock(
      generation: nextGeneration,
      tasks: activeTasks,
      labels: activeLabels,
    );
  }

  /// Checks whether [taskMap] contains any directed dependency cycle.
  static bool _hasDependencyCycle(Map<String, TaskItem> taskMap) {
    final state = <String, int>{};
    for (final id in taskMap.keys) {
      if ((state[id] ?? 0) == 0 && _visitCycleDfs(id, taskMap, state)) {
        return true;
      }
    }
    return false;
  }

  /// Returns whether [record] was already acknowledged in [baseline] when [discard] is true.
  static bool _isAcknowledgedInBaselineLabel(
    TdfDeletedLabelRecord record,
    TdfDeletedBlock? baseline, {
    required bool discard,
  }) {
    if (!discard || baseline == null) {
      return false;
    }
    final baseRecord = baseline.findLabelRecord(record.labelId);
    return baseRecord != null &&
        !record.deletedAt.isAfter(baseRecord.deletedAt);
  }

  /// Returns whether [record] was already acknowledged in [baseline] when [discard] is true.
  static bool _isAcknowledgedInBaselineTask(
    TdfDeletedTaskRecord record,
    TdfDeletedBlock? baseline, {
    required bool discard,
  }) {
    if (!discard || baseline == null) {
      return false;
    }
    final baseRecord = baseline.findTaskRecord(record.taskId);
    return baseRecord != null &&
        !record.deletedAt.isAfter(baseRecord.deletedAt);
  }

  /// Returns whether [label] is identical to [baseLabel] in payload and effective revision.
  static bool _isLabelUnchangedFromBaseline(
    TdfLabel label,
    TdfLabel baseLabel,
  ) {
    return label.effectiveModifiedAt == baseLabel.effectiveModifiedAt &&
        TdfPayloadComparison.compareLabelPayloads(label, baseLabel) == 0;
  }

  /// Returns whether [task] is identical to [baseTask] in payload, completions, and effective revision.
  static bool _isTaskUnchangedFromBaseline(TaskItem task, TaskItem baseTask) {
    return task.completions == baseTask.completions &&
        task.effectiveModifiedAt == baseTask.effectiveModifiedAt &&
        TdfPayloadComparison.compareTaskPayloads(task, baseTask) == 0;
  }

  /// Merges [primaryQueue] and [secondaryQueue] with [baselineQueue] and reconciles against [mergedTasks] per Section 6.11.2.
  static TdfQueueBlock _mergeQueueBlocks({
    required TdfQueueBlock primaryQueue,
    required TdfQueueBlock secondaryQueue,
    required TdfQueueBlock? baselineQueue,
    required Set<String> primaryTaskIds,
    required Set<String> secondaryTaskIds,
    required Set<String> undeletedTaskIds,
    required List<TaskItem> mergedTasks,
  }) {
    final openById = <String, TaskItem>{
      for (final task in mergedTasks)
        if (!task.isCompleted && task.completedAt == null) task.id: task,
    };

    final primaryWins =
        TdfPayloadComparison.compareQueueBlocks(primaryQueue, secondaryQueue) >=
        0;
    final winnerQueue = primaryWins ? primaryQueue : secondaryQueue;
    final loserQueue = primaryWins ? secondaryQueue : primaryQueue;
    final winnerBoardTaskIds = primaryWins ? primaryTaskIds : secondaryTaskIds;

    final List<String> baseSelectedIds;
    var appendConcurrentFromLoser = false;
    if (baselineQueue == null) {
      baseSelectedIds = winnerQueue.taskIds;
      appendConcurrentFromLoser = true;
    } else if (listEquals(primaryQueue.taskIds, secondaryQueue.taskIds)) {
      baseSelectedIds = primaryQueue.taskIds;
    } else if (listEquals(primaryQueue.taskIds, baselineQueue.taskIds)) {
      baseSelectedIds = secondaryQueue.taskIds;
    } else if (listEquals(secondaryQueue.taskIds, baselineQueue.taskIds)) {
      baseSelectedIds = primaryQueue.taskIds;
    } else {
      baseSelectedIds = winnerQueue.taskIds;
      appendConcurrentFromLoser = true;
    }

    final reconciledIds = <String>[];
    final seenInQueue = <String>{};
    for (final id in baseSelectedIds) {
      if (openById.containsKey(id) && seenInQueue.add(id)) {
        reconciledIds.add(id);
      }
    }

    final concurrentAdditions = <TaskItem>[];
    if (appendConcurrentFromLoser) {
      final baselineIdSet = baselineQueue?.taskIds.toSet();
      for (final id in loserQueue.taskIds) {
        final task = openById[id];
        if (task == null || seenInQueue.contains(id)) {
          continue;
        }
        final isConcurrentAddition = baselineIdSet != null
            ? (!baselineIdSet.contains(id) || undeletedTaskIds.contains(id))
            : (!winnerBoardTaskIds.contains(id) ||
                  undeletedTaskIds.contains(id));
        if (isConcurrentAddition && seenInQueue.add(id)) {
          concurrentAdditions.add(task);
        }
      }
    } else if (undeletedTaskIds.isNotEmpty) {
      for (final id in <String>[
        ...primaryQueue.taskIds,
        ...secondaryQueue.taskIds,
      ]) {
        final task = openById[id];
        if (task != null &&
            undeletedTaskIds.contains(id) &&
            seenInQueue.add(id)) {
          concurrentAdditions.add(task);
        }
      }
    }

    concurrentAdditions.sort(_compareConcurrentQueuedTasks);
    for (final task in concurrentAdditions) {
      reconciledIds.add(task.id);
    }

    if (reconciledIds.length > TdfQueueBlock.maxQueueEntries) {
      throw const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message: 'Merged queue block exceeds MAX_QUEUE_ENTRIES (4096).',
      );
    }

    var greatestQueue = winnerQueue;
    if (baselineQueue != null &&
        TdfPayloadComparison.compareQueueBlocks(baselineQueue, greatestQueue) >
            0) {
      greatestQueue = baselineQueue;
    }

    if (listEquals(greatestQueue.taskIds, reconciledIds)) {
      return TdfQueueBlock(
        modifiedAt: greatestQueue.modifiedAt,
        taskIds: reconciledIds,
      );
    }

    var maxMod = primaryQueue.modifiedAt.isAfter(secondaryQueue.modifiedAt)
        ? primaryQueue.modifiedAt
        : secondaryQueue.modifiedAt;
    if (baselineQueue != null && baselineQueue.modifiedAt.isAfter(maxMod)) {
      maxMod = baselineQueue.modifiedAt;
    }
    final nextMod = maxMod.add(const Duration(seconds: 1));
    if (!TdfCalendar.isWithinTimestampBounds(nextMod)) {
      throw const TdfException(
        kind: TdfErrorKind.invalidTimestamp,
        line: 1,
        message: 'Merged queue revision exceeds maximum supported timestamp.',
      );
    }
    return TdfQueueBlock(modifiedAt: nextMod, taskIds: reconciledIds);
  }

  /// Orders concurrent queue additions by ascending UTC `createdAt`, then ascending ASCII `id` per Section 6.11.2.
  static int _compareConcurrentQueuedTasks(TaskItem left, TaskItem right) {
    final cCmp = left.createdAt.compareTo(right.createdAt);
    if (cCmp != 0) {
      return cCmp;
    }
    return left.id.compareTo(right.id);
  }

  /// Reconciles all `label` blocks across [primaryLabels], [secondaryLabels], [baselineLabels], and [initialDeletedLabels].
  static _LabelReconciliationOutcome _reconcileLabels({
    required List<TdfLabel> primaryLabels,
    required List<TdfLabel> secondaryLabels,
    required List<TdfLabel>? baselineLabels,
    required Map<String, TdfDeletedLabelRecord> initialDeletedLabels,
    required Map<String, TdfDeletionResolution> resolutions,
    required int lGen,
    required int rGen,
    required int? effectiveAckGen,
    required bool requireAcknowledgedGeneration,
    required DateTime now,
  }) {
    final primaryMap = <String, TdfLabel>{
      for (final label in primaryLabels) label.id: label,
    };
    final secondaryMap = <String, TdfLabel>{
      for (final label in secondaryLabels) label.id: label,
    };
    final baselineMap = baselineLabels != null
        ? <String, TdfLabel>{
            for (final label in baselineLabels) label.id: label,
          }
        : null;
    final deletedById = <String, TdfDeletedLabelRecord>{
      ...initialDeletedLabels,
    };
    final orderedIds = _collectOrderedKeys(primaryMap.keys, secondaryMap.keys);

    final liveLabels = <TdfLabel>[];
    final conflictedIds = <String>[];
    final ambiguousIds = <String>[];
    var retiredByUndelete = false;

    for (final id in orderedIds) {
      final retired = _reconcileSingleLabel(
        id: id,
        primaryLabel: primaryMap[id],
        secondaryLabel: secondaryMap[id],
        baselineLabel: baselineMap?[id],
        hasBaseline: baselineMap != null,
        deletedById: deletedById,
        resolutions: resolutions,
        lGen: lGen,
        rGen: rGen,
        effectiveAckGen: effectiveAckGen,
        requireAcknowledgedGeneration: requireAcknowledgedGeneration,
        now: now,
        liveLabels: liveLabels,
        conflictedIds: conflictedIds,
        ambiguousIds: ambiguousIds,
      );
      if (retired) {
        retiredByUndelete = true;
      }
    }

    return _LabelReconciliationOutcome(
      liveLabels: liveLabels,
      deletedLabelsById: deletedById,
      conflictedIds: conflictedIds,
      ambiguousIds: ambiguousIds,
      retiredByUndelete: retiredByUndelete,
    );
  }

  /// Reconciles a single label [id] and returns whether an explicit `Undelete` retired a deletion record.
  static bool _reconcileSingleLabel({
    required String id,
    required TdfLabel? primaryLabel,
    required TdfLabel? secondaryLabel,
    required TdfLabel? baselineLabel,
    required bool hasBaseline,
    required Map<String, TdfDeletedLabelRecord> deletedById,
    required Map<String, TdfDeletionResolution> resolutions,
    required int lGen,
    required int rGen,
    required int? effectiveAckGen,
    required bool requireAcknowledgedGeneration,
    required DateTime now,
    required List<TdfLabel> liveLabels,
    required List<String> conflictedIds,
    required List<String> ambiguousIds,
  }) {
    if (primaryLabel != null && secondaryLabel != null) {
      liveLabels.add(
        TdfPayloadComparison.mergeLabelWithBaseline(
          local: primaryLabel,
          incoming: secondaryLabel,
          baseline: baselineLabel,
        ),
      );
      return false;
    }

    final surviving = primaryLabel ?? secondaryLabel;
    if (surviving == null) {
      return false;
    }
    final isFromPrimary = primaryLabel != null;
    final existingDeleted = deletedById[id];

    if (existingDeleted != null) {
      if (baselineLabel != null &&
          _isLabelUnchangedFromBaseline(surviving, baselineLabel)) {
        return false;
      }
      return _resolveLabelDeletionConflict(
        id: id,
        surviving: surviving,
        baselineLabel: baselineLabel,
        deletedRecord: existingDeleted,
        resolution: resolutions[id],
        now: now,
        deletedById: deletedById,
        liveLabels: liveLabels,
        conflictedIds: conflictedIds,
      );
    }

    final genAdvanced =
        lGen != rGen ||
        (effectiveAckGen != null &&
            (lGen > effectiveAckGen || rGen > effectiveAckGen));
    if (baselineLabel != null) {
      if (_isLabelUnchangedFromBaseline(surviving, baselineLabel)) {
        if (!genAdvanced) {
          final synthDeletedAt = TaskItem.nextModifiedTimestamp(
            now,
            baselineLabel.effectiveModifiedAt,
          );
          deletedById[id] = TdfDeletedLabelRecord(
            labelId: id,
            deletedAt: synthDeletedAt,
          );
        }
        return false;
      }
      if (genAdvanced) {
        ambiguousIds.add(id);
        return false;
      }
      final synthDeletedAt = TaskItem.nextModifiedTimestamp(
        now,
        baselineLabel.effectiveModifiedAt,
      );
      final synthRecord = TdfDeletedLabelRecord(
        labelId: id,
        deletedAt: synthDeletedAt,
      );
      return _resolveLabelDeletionConflict(
        id: id,
        surviving: surviving,
        baselineLabel: baselineLabel,
        deletedRecord: synthRecord,
        resolution: resolutions[id],
        now: now,
        deletedById: deletedById,
        liveLabels: liveLabels,
        conflictedIds: conflictedIds,
      );
    }

    final survivingSideOutdated = isFromPrimary
        ? (rGen > (effectiveAckGen ?? lGen) ||
              (requireAcknowledgedGeneration && effectiveAckGen == null))
        : (lGen > (effectiveAckGen ?? rGen));
    if (survivingSideOutdated || (!hasBaseline && genAdvanced)) {
      ambiguousIds.add(id);
      return false;
    }

    liveLabels.add(surviving);
    return false;
  }

  /// Reconciles a single task [id] and returns whether an explicit `Undelete` retired a deletion record.
  static bool _reconcileSingleTask({
    required String id,
    required TaskItem? primaryTask,
    required TaskItem? secondaryTask,
    required TaskItem? baselineTask,
    required bool hasBaseline,
    required Map<String, TdfDeletedTaskRecord> deletedById,
    required Map<String, TdfDeletionResolution> resolutions,
    required int lGen,
    required int rGen,
    required int? effectiveAckGen,
    required bool requireAcknowledgedGeneration,
    required DateTime now,
    required List<TaskItem> liveTasks,
    required List<String> conflictedIds,
    required List<String> ambiguousIds,
  }) {
    if (primaryTask != null && secondaryTask != null) {
      liveTasks.add(
        TdfPayloadComparison.mergeTaskWithBaseline(
          local: primaryTask,
          incoming: secondaryTask,
          baseline: baselineTask,
        ),
      );
      return false;
    }

    final surviving = primaryTask ?? secondaryTask;
    if (surviving == null) {
      return false;
    }
    final isFromPrimary = primaryTask != null;
    final existingDeleted = deletedById[id];

    if (existingDeleted != null) {
      if (baselineTask != null &&
          _isTaskUnchangedFromBaseline(surviving, baselineTask)) {
        final maxComp = _max3Int(
          existingDeleted.completionsCheckpoint,
          surviving.completions,
          baselineTask.completions,
        );
        deletedById[id] = TdfDeletedTaskRecord(
          taskId: id,
          deletedAt: existingDeleted.deletedAt,
          completionsCheckpoint: maxComp,
        );
        return false;
      }
      return _resolveTaskDeletionConflict(
        id: id,
        surviving: surviving,
        baselineTask: baselineTask,
        deletedRecord: existingDeleted,
        resolution: resolutions[id],
        now: now,
        deletedById: deletedById,
        liveTasks: liveTasks,
        conflictedIds: conflictedIds,
      );
    }

    final genAdvanced =
        lGen != rGen ||
        (effectiveAckGen != null &&
            (lGen > effectiveAckGen || rGen > effectiveAckGen));
    if (baselineTask != null) {
      if (_isTaskUnchangedFromBaseline(surviving, baselineTask)) {
        if (!genAdvanced) {
          final synthDeletedAt = TaskItem.nextModifiedTimestamp(
            now,
            baselineTask.effectiveModifiedAt,
          );
          deletedById[id] = TdfDeletedTaskRecord(
            taskId: id,
            deletedAt: synthDeletedAt,
            completionsCheckpoint: baselineTask.completions,
          );
        }
        return false;
      }
      if (genAdvanced) {
        ambiguousIds.add(id);
        return false;
      }
      final synthDeletedAt = TaskItem.nextModifiedTimestamp(
        now,
        baselineTask.effectiveModifiedAt,
      );
      final synthRecord = TdfDeletedTaskRecord(
        taskId: id,
        deletedAt: synthDeletedAt,
        completionsCheckpoint: baselineTask.completions,
      );
      return _resolveTaskDeletionConflict(
        id: id,
        surviving: surviving,
        baselineTask: baselineTask,
        deletedRecord: synthRecord,
        resolution: resolutions[id],
        now: now,
        deletedById: deletedById,
        liveTasks: liveTasks,
        conflictedIds: conflictedIds,
      );
    }

    final survivingSideOutdated = isFromPrimary
        ? (rGen > (effectiveAckGen ?? lGen) ||
              (requireAcknowledgedGeneration && effectiveAckGen == null))
        : (lGen > (effectiveAckGen ?? rGen));
    if (survivingSideOutdated || (!hasBaseline && genAdvanced)) {
      ambiguousIds.add(id);
      return false;
    }

    liveTasks.add(surviving);
    return false;
  }

  /// Reconciles all `task` blocks across [primaryTasks], [secondaryTasks], [baselineTasks], and [initialDeletedTasks].
  static _TaskReconciliationOutcome _reconcileTasks({
    required List<TaskItem> primaryTasks,
    required List<TaskItem> secondaryTasks,
    required List<TaskItem>? baselineTasks,
    required Map<String, TdfDeletedTaskRecord> initialDeletedTasks,
    required Map<String, TdfDeletionResolution> resolutions,
    required int lGen,
    required int rGen,
    required int? effectiveAckGen,
    required bool requireAcknowledgedGeneration,
    required DateTime now,
  }) {
    final primaryMap = <String, TaskItem>{
      for (final task in primaryTasks) task.id: task,
    };
    final secondaryMap = <String, TaskItem>{
      for (final task in secondaryTasks) task.id: task,
    };
    final baselineMap = baselineTasks != null
        ? <String, TaskItem>{for (final task in baselineTasks) task.id: task}
        : null;
    final deletedById = <String, TdfDeletedTaskRecord>{...initialDeletedTasks};
    final orderedIds = _collectOrderedKeys(primaryMap.keys, secondaryMap.keys);

    final liveTasks = <TaskItem>[];
    final conflictedIds = <String>[];
    final ambiguousIds = <String>[];
    var retiredByUndelete = false;

    for (final id in orderedIds) {
      final retired = _reconcileSingleTask(
        id: id,
        primaryTask: primaryMap[id],
        secondaryTask: secondaryMap[id],
        baselineTask: baselineMap?[id],
        hasBaseline: baselineMap != null,
        deletedById: deletedById,
        resolutions: resolutions,
        lGen: lGen,
        rGen: rGen,
        effectiveAckGen: effectiveAckGen,
        requireAcknowledgedGeneration: requireAcknowledgedGeneration,
        now: now,
        liveTasks: liveTasks,
        conflictedIds: conflictedIds,
        ambiguousIds: ambiguousIds,
      );
      if (retired) {
        retiredByUndelete = true;
      }
    }

    return _TaskReconciliationOutcome(
      liveTasks: liveTasks,
      deletedTasksById: deletedById,
      conflictedIds: conflictedIds,
      ambiguousIds: ambiguousIds,
      retiredByUndelete: retiredByUndelete,
    );
  }

  /// Applies [resolution] (or records a `DeletionConflict`) for label [id] per Section 6.8.2.
  static bool _resolveLabelDeletionConflict({
    required String id,
    required TdfLabel surviving,
    required TdfLabel? baselineLabel,
    required TdfDeletedLabelRecord deletedRecord,
    required TdfDeletionResolution? resolution,
    required DateTime now,
    required Map<String, TdfDeletedLabelRecord> deletedById,
    required List<TdfLabel> liveLabels,
    required List<String> conflictedIds,
  }) {
    if (resolution == null) {
      conflictedIds.add(id);
      return false;
    }
    final decisionRevision = _computeDecisionRevision(
      now,
      surviving.effectiveModifiedAt,
      deletedRecord.deletedAt,
      baselineLabel?.effectiveModifiedAt,
    );
    switch (resolution) {
      case TdfDeletionResolution.delete:
        deletedById[id] = TdfDeletedLabelRecord(
          labelId: id,
          deletedAt: decisionRevision,
        );
        return false;
      case TdfDeletionResolution.undelete:
        deletedById.remove(id);
        liveLabels.add(surviving.copyWith(modifiedAt: decisionRevision));
        return true;
    }
  }

  /// Applies [resolution] (or records a `DeletionConflict`) for task [id] per Section 6.8.2.
  static bool _resolveTaskDeletionConflict({
    required String id,
    required TaskItem surviving,
    required TaskItem? baselineTask,
    required TdfDeletedTaskRecord deletedRecord,
    required TdfDeletionResolution? resolution,
    required DateTime now,
    required Map<String, TdfDeletedTaskRecord> deletedById,
    required List<TaskItem> liveTasks,
    required List<String> conflictedIds,
  }) {
    if (resolution == null) {
      conflictedIds.add(id);
      return false;
    }
    final decisionRevision = _computeDecisionRevision(
      now,
      surviving.effectiveModifiedAt,
      deletedRecord.deletedAt,
      baselineTask?.effectiveModifiedAt,
    );
    final maxComp = _max3Int(
      surviving.completions,
      baselineTask?.completions ?? 0,
      deletedRecord.completionsCheckpoint,
    );
    switch (resolution) {
      case TdfDeletionResolution.delete:
        deletedById[id] = TdfDeletedTaskRecord(
          taskId: id,
          deletedAt: decisionRevision,
          completionsCheckpoint: maxComp,
        );
        return false;
      case TdfDeletionResolution.undelete:
        deletedById.remove(id);
        liveTasks.add(
          surviving.copyWith(
            completions: maxComp,
            modifiedAt: decisionRevision,
          ),
        );
        return true;
    }
  }

  /// Rewrites a recovered [task] with [newId] and remapped `labelIds` and `dependencies` per Section 6.8.4.
  static TaskItem _rewriteRecoveredTask({
    required TaskItem task,
    required String newId,
    required Map<String, String> labelIdMap,
    required Map<String, String> taskIdMap,
    required DateTime now,
  }) {
    final remappedLabels = <String>[
      for (final labelId in task.labelIds) labelIdMap[labelId] ?? labelId,
    ];
    final remappedDeps = <TdfTaskDependency>[
      for (final dep in task.dependencies)
        TdfTaskDependency(
          taskId: taskIdMap[dep.taskId] ?? dep.taskId,
          requiredCompletion: dep.requiredCompletion,
        ),
    ];
    final nextMod = TaskItem.nextModifiedTimestamp(
      now,
      task.effectiveModifiedAt,
    );
    return TaskItem(
      id: newId,
      title: task.title,
      note: task.note,
      createdAt: task.createdAt,
      completedAt: task.completedAt,
      modifiedAt: nextMod,
      completions: task.completions,
      isPriority: task.isPriority,
      suspendedAt: task.suspendedAt,
      isSuspendedForever: task.isSuspendedForever,
      repeatRule: task.repeatRule,
      labelIds: remappedLabels,
      dependencies: remappedDeps,
      links: task.links,
      conditions: task.conditions,
      subtasksAutoFinish: task.subtasksAutoFinish,
      subtasks: task.subtasks,
    );
  }

  /// Strips deleted labels from [tasks] (advancing affected tasks' `modified` timestamp)
  /// and validates that no unknown label references remain per Sections 6.7.7 and 6.8.1.
  static List<TaskItem> _stripDeletedLabelsAndValidateReferences({
    required List<TaskItem> tasks,
    required Set<String> validLabelIds,
    required Map<String, TdfDeletedLabelRecord> deletedLabelsById,
    required List<TdfLabel>? baselineLabels,
  }) {
    final baselineLabelSet = <String>{
      if (baselineLabels != null)
        for (final label in baselineLabels) label.id,
    };
    return <TaskItem>[
      for (final task in tasks)
        _stripDeletedLabelsFromSingleTask(
          task: task,
          validLabelIds: validLabelIds,
          deletedLabelsById: deletedLabelsById,
          baselineLabelSet: baselineLabelSet,
        ),
    ];
  }

  /// Strips deleted labels from a single [task] and validates remaining label references.
  static TaskItem _stripDeletedLabelsFromSingleTask({
    required TaskItem task,
    required Set<String> validLabelIds,
    required Map<String, TdfDeletedLabelRecord> deletedLabelsById,
    required Set<String> baselineLabelSet,
  }) {
    if (task.labelIds.isEmpty) {
      return task;
    }
    final retained = <String>[];
    DateTime? latestLabelDeletion;
    var strippedAny = false;

    for (final labelId in task.labelIds) {
      if (validLabelIds.contains(labelId)) {
        retained.add(labelId);
        continue;
      }
      final delRecord = deletedLabelsById[labelId];
      if (delRecord != null || baselineLabelSet.contains(labelId)) {
        strippedAny = true;
        if (delRecord != null &&
            (latestLabelDeletion == null ||
                delRecord.deletedAt.isAfter(latestLabelDeletion))) {
          latestLabelDeletion = delRecord.deletedAt;
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

    if (!strippedAny) {
      return task;
    }
    var baseMod = task.effectiveModifiedAt;
    if (latestLabelDeletion != null && latestLabelDeletion.isAfter(baseMod)) {
      baseMod = latestLabelDeletion;
    }
    final nextMod = baseMod.add(const Duration(seconds: 1));
    return task.copyWith(labelIds: retained, modifiedAt: nextMod);
  }

  /// Validates the combined dependency graph for cycles and checks Section 7 resource bounds.
  static void _validateMergedGraphAndBounds({
    required List<TaskItem> tasks,
    required List<TdfLabel> labels,
  }) {
    if (tasks.length + labels.length + 2 > TdfService.maxBlocksPerDoc) {
      throw const TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 1,
        message: 'Merged document exceeds MAX_BLOCKS_PER_DOC (4096).',
      );
    }
    final taskMap = <String, TaskItem>{for (final task in tasks) task.id: task};
    if (_hasDependencyCycle(taskMap)) {
      throw const TdfException(
        kind: TdfErrorKind.circularDependency,
        line: 1,
        message: 'Merged document contains a circular task dependency.',
      );
    }
  }

  /// Verifies that deletion history generations have not rolled back and task completion counters have not regressed.
  static void _verifyGenerationsAndCompletionHistory({
    required TaskBoard primary,
    required TaskBoard secondary,
    required TaskBoard? baseline,
    required int? effectiveAckGen,
  }) {
    final lGen = primary.deletedBlock.generation;
    final rGen = secondary.deletedBlock.generation;
    if (effectiveAckGen != null &&
        (lGen < effectiveAckGen || rGen < effectiveAckGen)) {
      throw const TdfSyncOutcomeException(
        kind: TdfSyncOutcomeKind.syncGenerationRollback,
        message: 'Shared deletion history generation is lower than the acknowledged generation.',
      );
    }
    if (baseline == null) {
      return;
    }
    final primaryMap = <String, TaskItem>{
      for (final task in primary.allTasks) task.id: task,
    };
    final secondaryMap = <String, TaskItem>{
      for (final task in secondary.allTasks) task.id: task,
    };
    final regressedIds = <String>[];
    for (final baseTask in baseline.allTasks) {
      final pTask = primaryMap[baseTask.id];
      final sTask = secondaryMap[baseTask.id];
      if ((pTask != null && pTask.completions < baseTask.completions) ||
          (sTask != null && sTask.completions < baseTask.completions)) {
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

  /// Recursive DFS helper for cycle detection (`0` = unvisited, `1` = visiting, `2` = visited).
  static bool _visitCycleDfs(
    String currentId,
    Map<String, TaskItem> taskMap,
    Map<String, int> state,
  ) {
    state[currentId] = 1;
    final task = taskMap[currentId];
    if (task != null) {
      for (final dep in task.dependencies) {
        final targetId = dep.taskId;
        if (targetId == currentId) {
          return true;
        }
        if (!taskMap.containsKey(targetId)) {
          continue;
        }
        final targetState = state[targetId] ?? 0;
        if (targetState == 1) {
          return true;
        }
        if (targetState == 0 && _visitCycleDfs(targetId, taskMap, state)) {
          return true;
        }
      }
    }
    state[currentId] = 2;
    return false;
  }

  /// Returns the maximum of three integers.
  static int _max3Int(int a, int b, int c) {
    final ab = a >= b ? a : b;
    return ab >= c ? ab : c;
  }
}

/// Immutable per-workspace synchronization baseline, acknowledged generations, and label deletion state.
@immutable
class WorkspaceSyncState {
  /// Creates a [WorkspaceSyncState].
  WorkspaceSyncState({
    this.lastSyncedLocalTdf,
    this.lastSyncedRemoteTdf,
    Map<String, DateTime> deletedLabelTimestamps = const {},
    this.acknowledgedLocalGeneration = 0,
    this.acknowledgedRemoteGeneration = 0,
  }) : deletedLabelTimestamps = Map<String, DateTime>.unmodifiable(
         <String, DateTime>{
           for (final entry in deletedLabelTimestamps.entries)
             entry.key: TaskItem.normalizeTimestamp(entry.value),
         },
       );

  const WorkspaceSyncState._empty()
    : lastSyncedLocalTdf = null,
      lastSyncedRemoteTdf = null,
      deletedLabelTimestamps = const <String, DateTime>{},
      acknowledgedLocalGeneration = 0,
      acknowledgedRemoteGeneration = 0;

  /// Reconstructs a [WorkspaceSyncState] from its compact `TTS\x01` or `TTS\x02` binary payload,
  /// returning [empty] if [bytes] is empty or malformed.
  factory WorkspaceSyncState.fromBytes(List<int> bytes) {
    if (bytes.length < 6 ||
        bytes[0] != 0x54 ||
        bytes[1] != 0x54 ||
        bytes[2] != 0x53 ||
        (bytes[3] != _binaryVersionV1 && bytes[3] != _binaryVersionV2)) {
      return empty;
    }
    final version = bytes[3];
    final source = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    try {
      final (localTdf, afterLocal) = _readNullableString(source, 4);
      final (remoteTdf, afterRemote) = _readNullableString(source, afterLocal);
      if (afterRemote + 2 > source.length) {
        return empty;
      }
      final count = (source[afterRemote] << 8) | source[afterRemote + 1];
      var cursor = afterRemote + 2;
      final deletedMap = <String, DateTime>{};
      for (var i = 0; i < count; i++) {
        final (labelId, dateVal, nextCursor) = _readDeletedLabelEntry(
          source,
          cursor,
        );
        deletedMap[labelId] = dateVal;
        cursor = nextCursor;
      }
      var localGen = 0;
      var remoteGen = 0;
      if (version == _binaryVersionV2) {
        if (cursor + 16 != source.length) {
          return empty;
        }
        localGen = _readInt64(source, cursor);
        remoteGen = _readInt64(source, cursor + 8);
        cursor += 16;
      }
      if (cursor != source.length) {
        return empty;
      }
      return WorkspaceSyncState(
        lastSyncedLocalTdf: localTdf,
        lastSyncedRemoteTdf: remoteTdf,
        deletedLabelTimestamps: deletedMap,
        acknowledgedLocalGeneration: localGen,
        acknowledgedRemoteGeneration: remoteGen,
      );
    } on FormatException {
      return empty;
    }
  }

  /// Empty synchronization state with no baselines and no pending label deletions.
  static const WorkspaceSyncState empty = WorkspaceSyncState._empty();

  static const int _binaryVersionV1 = 1;
  static const int _binaryVersionV2 = 2;
  static const Utf8Codec _utf8Codec = Utf8Codec(allowMalformed: false);

  /// Last acknowledged `deleted.generation` for the local `.tdf` file.
  final int acknowledgedLocalGeneration;

  /// Last acknowledged `deleted.generation` for the remote WebDAV `.tdf` file.
  final int acknowledgedRemoteGeneration;

  /// UTC deletion timestamps (`T_del`) for labels deleted since the last full sync.
  final Map<String, DateTime> deletedLabelTimestamps;

  /// Canonical `.tdf` snapshot from the last successful local file synchronization.
  final String? lastSyncedLocalTdf;

  /// Canonical `.tdf` snapshot from the last successful WebDAV synchronization.
  final String? lastSyncedRemoteTdf;

  /// Returns a copy of this [WorkspaceSyncState] with updated fields.
  WorkspaceSyncState copyWith({
    String? lastSyncedLocalTdf,
    bool clearLastSyncedLocalTdf = false,
    String? lastSyncedRemoteTdf,
    bool clearLastSyncedRemoteTdf = false,
    Map<String, DateTime>? deletedLabelTimestamps,
    int? acknowledgedLocalGeneration,
    int? acknowledgedRemoteGeneration,
  }) {
    return WorkspaceSyncState(
      lastSyncedLocalTdf: clearLastSyncedLocalTdf
          ? null
          : (lastSyncedLocalTdf ?? this.lastSyncedLocalTdf),
      lastSyncedRemoteTdf: clearLastSyncedRemoteTdf
          ? null
          : (lastSyncedRemoteTdf ?? this.lastSyncedRemoteTdf),
      deletedLabelTimestamps:
          deletedLabelTimestamps ?? this.deletedLabelTimestamps,
      acknowledgedLocalGeneration:
          acknowledgedLocalGeneration ?? this.acknowledgedLocalGeneration,
      acknowledgedRemoteGeneration:
          acknowledgedRemoteGeneration ?? this.acknowledgedRemoteGeneration,
    );
  }

  /// Encodes this [WorkspaceSyncState] into a compact `TTS\x02` binary [Uint8List].
  Uint8List toBytes() {
    final builder = BytesBuilder(copy: false)
      ..add(const <int>[0x54, 0x54, 0x53, _binaryVersionV2]);
    _writeNullableString(builder, lastSyncedLocalTdf);
    _writeNullableString(builder, lastSyncedRemoteTdf);

    final entries = deletedLabelTimestamps.entries.toList();
    final count = entries.length <= 0xFFFF ? entries.length : 0xFFFF;
    builder
      ..addByte((count >> 8) & 0xFF)
      ..addByte(count & 0xFF);
    for (var i = 0; i < count; i++) {
      _writeDeletedLabelEntry(builder, entries[i].key, entries[i].value);
    }
    _writeInt64(builder, acknowledgedLocalGeneration);
    _writeInt64(builder, acknowledgedRemoteGeneration);
    return builder.toBytes();
  }

  /// Reads a single `(labelId, deletedAt, nextOffset)` entry from [source] at [offset].
  static (String, DateTime, int) _readDeletedLabelEntry(
    Uint8List source,
    int offset,
  ) {
    final (labelId, afterId) = _readNullableString(source, offset);
    if (labelId == null || labelId.isEmpty || afterId + 8 > source.length) {
      throw const FormatException('Invalid deleted label entry.');
    }
    final epochSeconds = _readInt64(source, afterId);
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      epochSeconds * 1000,
      isUtc: true,
    );
    return (labelId, TaskItem.normalizeTimestamp(timestamp), afterId + 8);
  }

  /// Reads a big-endian 64-bit integer from [source] at [offset].
  static int _readInt64(Uint8List source, int offset) {
    var value = 0;
    for (var i = 0; i < 8; i++) {
      value = (value << 8) | source[offset + i];
    }
    return value;
  }

  /// Reads a 32-bit length-prefixed nullable UTF-8 string from [source] at [offset].
  static (String?, int) _readNullableString(Uint8List source, int offset) {
    if (offset >= source.length) {
      throw const FormatException('Truncated string flag.');
    }
    final present = source[offset];
    if (present == 0) {
      return (null, offset + 1);
    }
    if (present != 1 || offset + 5 > source.length) {
      throw const FormatException('Invalid string header.');
    }
    final length =
        (source[offset + 1] << 24) |
        (source[offset + 2] << 16) |
        (source[offset + 3] << 8) |
        source[offset + 4];
    final start = offset + 5;
    final end = start + length;
    if (length < 0 || end > source.length) {
      throw const FormatException('Truncated string bytes.');
    }
    final decoded = _utf8Codec.decode(
      Uint8List.sublistView(source, start, end),
    );
    return (decoded, end);
  }

  /// Appends a single `(labelId, deletedAt)` entry to [builder].
  static void _writeDeletedLabelEntry(
    BytesBuilder builder,
    String labelId,
    DateTime deletedAt,
  ) {
    _writeNullableString(builder, labelId);
    final epochSeconds =
        TaskItem.normalizeTimestamp(deletedAt).millisecondsSinceEpoch ~/ 1000;
    _writeInt64(builder, epochSeconds);
  }

  /// Appends a big-endian 64-bit integer [value] to [builder].
  static void _writeInt64(BytesBuilder builder, int value) {
    for (var shift = 56; shift >= 0; shift -= 8) {
      builder.addByte((value >> shift) & 0xFF);
    }
  }

  /// Appends a nullable UTF-8 [value] to [builder] with a 1-byte presence flag and 32-bit length.
  static void _writeNullableString(BytesBuilder builder, String? value) {
    if (value == null) {
      builder.addByte(0);
      return;
    }
    final encoded = _utf8Codec.encode(value);
    final len = encoded.length;
    builder
      ..addByte(1)
      ..addByte((len >> 24) & 0xFF)
      ..addByte((len >> 16) & 0xFF)
      ..addByte((len >> 8) & 0xFF)
      ..addByte(len & 0xFF)
      ..add(encoded);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WorkspaceSyncState &&
        other.lastSyncedLocalTdf == lastSyncedLocalTdf &&
        other.lastSyncedRemoteTdf == lastSyncedRemoteTdf &&
        other.acknowledgedLocalGeneration == acknowledgedLocalGeneration &&
        other.acknowledgedRemoteGeneration == acknowledgedRemoteGeneration &&
        mapEquals(other.deletedLabelTimestamps, deletedLabelTimestamps);
  }

  @override
  int get hashCode => Object.hash(
    lastSyncedLocalTdf,
    lastSyncedRemoteTdf,
    acknowledgedLocalGeneration,
    acknowledgedRemoteGeneration,
    Object.hashAllUnordered(
      deletedLabelTimestamps.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
  );
}

/// Internal result of reconciling `label` blocks and label deletion records.
@immutable
class _LabelReconciliationOutcome {
  const _LabelReconciliationOutcome({
    required this.liveLabels,
    required this.deletedLabelsById,
    required this.conflictedIds,
    required this.ambiguousIds,
    required this.retiredByUndelete,
  });

  final List<String> ambiguousIds;
  final List<String> conflictedIds;
  final Map<String, TdfDeletedLabelRecord> deletedLabelsById;
  final List<TdfLabel> liveLabels;
  final bool retiredByUndelete;
}

/// Internal result of reconciling `task` blocks and task deletion records.
@immutable
class _TaskReconciliationOutcome {
  const _TaskReconciliationOutcome({
    required this.liveTasks,
    required this.deletedTasksById,
    required this.conflictedIds,
    required this.ambiguousIds,
    required this.retiredByUndelete,
  });

  final List<String> ambiguousIds;
  final List<String> conflictedIds;
  final Map<String, TdfDeletedTaskRecord> deletedTasksById;
  final List<TaskItem> liveTasks;
  final bool retiredByUndelete;
}
