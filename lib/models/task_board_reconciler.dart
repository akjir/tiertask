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
import 'task_item.dart';
import 'tdf_error.dart';
import 'tdf_location.dart';
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

/// Result of reconciling `location` blocks and location deletion records.
@immutable
class LocationReconciliationOutcome {
  /// Creates a [LocationReconciliationOutcome].
  const LocationReconciliationOutcome({
    required this.liveLocations,
    required this.deletedLocationsById,
    required this.conflictedIds,
    required this.ambiguousIds,
    required this.retiredByUndelete,
  });

  /// Location IDs requiring user recovery after deletion history expiry.
  final List<String> ambiguousIds;

  /// Location IDs with unresolved deletion vs. modification conflicts.
  final List<String> conflictedIds;

  /// Active location deletion records keyed by location ID.
  final Map<String, TdfDeletedLocationRecord> deletedLocationsById;

  /// Surviving reconciled live locations.
  final List<TdfLocation> liveLocations;

  /// Whether at least one deletion record was retired by an explicit undelete resolution.
  final bool retiredByUndelete;
}

/// Stateless per-entity three-way location, label, and task reconciliation engine for `TaskBoardSync`.
@immutable
class TaskBoardReconciler {
  /// Prevents instantiation of this stateless helper class.
  const TaskBoardReconciler._();

  /// Throws a [TdfSyncOutcomeException] when [locations], [labels], or [tasks] recorded deletion conflicts or ambiguous recovery items.
  static void checkSyncOutcomes(
    LabelReconciliationOutcome labels,
    TaskReconciliationOutcome tasks, [
    LocationReconciliationOutcome? locations,
  ]) {
    final locConflicts = locations?.conflictedIds ?? const <String>[];
    final locAmbiguous = locations?.ambiguousIds ?? const <String>[];
    if (tasks.conflictedIds.isNotEmpty ||
        labels.conflictedIds.isNotEmpty ||
        locConflicts.isNotEmpty) {
      AppLogger.event(
        LogLevel.warn,
        LogTag.sync,
        'sync.conflict',
        fields: <String, Object?>{
          'kind': 'deletion_conflict',
          'tasks': tasks.conflictedIds.length,
          'labels': labels.conflictedIds.length,
          'locations': locConflicts.length,
        },
      );
      throw TdfSyncOutcomeException(
        kind: TdfSyncOutcomeKind.deletionConflict,
        conflictedTaskIds: List<String>.unmodifiable(tasks.conflictedIds),
        conflictedLabelIds: List<String>.unmodifiable(labels.conflictedIds),
        conflictedLocationIds: List<String>.unmodifiable(locConflicts),
        message: 'Entity deletion conflicts with concurrent live modification.',
      );
    }
    if (tasks.ambiguousIds.isNotEmpty ||
        labels.ambiguousIds.isNotEmpty ||
        locAmbiguous.isNotEmpty) {
      AppLogger.event(
        LogLevel.warn,
        LogTag.sync,
        'sync.conflict',
        fields: <String, Object?>{
          'kind': 'recovery_required',
          'tasks': tasks.ambiguousIds.length,
          'labels': labels.ambiguousIds.length,
          'locations': locAmbiguous.length,
        },
      );
      throw TdfSyncOutcomeException(
        kind: TdfSyncOutcomeKind.recoveryRequired,
        ambiguousTaskIds: List<String>.unmodifiable(tasks.ambiguousIds),
        ambiguousLabelIds: List<String>.unmodifiable(labels.ambiguousIds),
        ambiguousLocationIds: List<String>.unmodifiable(locAmbiguous),
        message: 'Ambiguous local entities require user recovery after deletion history expiry.',
      );
    }
  }

  /// Computes newly introduced label references $A_L(T) \cup A_R(T)$ across tasks relative to [boards]'s baseline per Section 6.8.2.
  static Set<String> computeNewlyReferencedLabelIds(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    Map<String, TdfDeletedTaskRecord> initialDeletedTasks,
  ) {
    final (primary, secondary, baseline) = boards;
    if (baseline == null) {
      return const <String>{};
    }
    final baseTaskMap = _indexById(baseline.allTasks, (task) => task.id);
    final newlyReferenced = <String>{};
    for (final task in <TaskItem>[...primary.allTasks, ...secondary.allTasks]) {
      final baseTask = baseTaskMap[task.id];
      if (baseTask != null) {
        _collectAddedStrings(task.labelIds, baseTask.labelIds, newlyReferenced);
      } else if (!initialDeletedTasks.containsKey(task.id)) {
        newlyReferenced.addAll(task.labelIds);
      }
    }
    return newlyReferenced;
  }

  /// Computes newly introduced location references $A^{\text{loc}}_L(E) \cup A^{\text{loc}}_R(E)$ across tasks and labels relative to [boards]'s baseline per Section 6.8.2.
  static Set<String> computeNewlyReferencedLocationIds(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    Map<String, TdfDeletedTaskRecord> initialDeletedTasks,
    Map<String, TdfDeletedLabelRecord> initialDeletedLabels,
  ) {
    final (primary, secondary, baseline) = boards;
    if (baseline == null) {
      return const <String>{};
    }
    final baseTaskMap = _indexById(baseline.allTasks, (task) => task.id);
    final baseLabelMap = _indexById(baseline.labels, (label) => label.id);
    final newlyReferenced = <String>{};

    for (final task in <TaskItem>[...primary.allTasks, ...secondary.allTasks]) {
      final taskLocs = _extractLocationIds(task.conditions);
      final baseTask = baseTaskMap[task.id];
      if (baseTask != null) {
        final baseLocs = _extractLocationIds(baseTask.conditions);
        _collectAddedStrings(taskLocs, baseLocs, newlyReferenced);
      } else if (!initialDeletedTasks.containsKey(task.id)) {
        newlyReferenced.addAll(taskLocs);
      }
    }
    for (final label in <TdfLabel>[...primary.labels, ...secondary.labels]) {
      final labelLocs = _extractLocationIds(label.conditions);
      final baseLabel = baseLabelMap[label.id];
      if (baseLabel != null) {
        final baseLocs = _extractLocationIds(baseLabel.conditions);
        _collectAddedStrings(labelLocs, baseLocs, newlyReferenced);
      } else if (!initialDeletedLabels.containsKey(label.id)) {
        newlyReferenced.addAll(labelLocs);
      }
    }
    return newlyReferenced;
  }

  /// Reconciles all `label` blocks across [boards], [initialDeleted], [resolutions], and [options].
  static LabelReconciliationOutcome reconcileLabels(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    Map<String, TdfDeletedLabelRecord> initialDeleted,
    Map<String, TdfDeletionResolution> resolutions,
    (int?, bool, DateTime) options, {
    Set<String> tombstonedLocationIds = const <String>{},
    Set<String> newlyReferencedLabelIds = const <String>{},
  }) {
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
      if (_reconcileSingleLabel(
        id,
        pair,
        context,
        accumulator,
        tombstonedLocationIds: tombstonedLocationIds,
        newlyReferencedLabelIds: newlyReferencedLabelIds,
      )) {
        retired = true;
      }
    }
    return LabelReconciliationOutcome(
      liveLabels: accumulator.live,
      deletedLabelsById: accumulator.deleted,
      conflictedIds: accumulator.conflicted,
      ambiguousIds: accumulator.ambiguous,
      retiredByUndelete: retired,
    );
  }

  /// Reconciles all `location` blocks across [boards], [initialDeleted], [resolutions], and [options].
  static LocationReconciliationOutcome reconcileLocations(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    Map<String, TdfDeletedLocationRecord> initialDeleted,
    Map<String, TdfDeletionResolution> resolutions,
    (int?, bool, DateTime) options, {
    Set<String> newlyReferencedLocationIds = const <String>{},
  }) {
    final (primary, secondary, baseline) = boards;
    final primaryMap = _indexById(primary.locations, (loc) => loc.id);
    final secondaryMap = _indexById(secondary.locations, (loc) => loc.id);
    final baselineMap = baseline != null
        ? _indexById(baseline.locations, (loc) => loc.id)
        : null;
    final context = _reconcileContext(boards, resolutions, options);
    final accumulator = (
      live: <TdfLocation>[],
      deleted: <String, TdfDeletedLocationRecord>{...initialDeleted},
      conflicted: <String>[],
      ambiguous: <String>[],
    );
    var retired = false;
    for (final id in <String>{...primaryMap.keys, ...secondaryMap.keys}) {
      final pair = (primaryMap[id], secondaryMap[id], baselineMap?[id]);
      if (_reconcileSingleLocation(
        id,
        pair,
        context,
        accumulator,
        newlyReferencedLocationIds: newlyReferencedLocationIds,
      )) {
        retired = true;
      }
    }
    return LocationReconciliationOutcome(
      liveLocations: accumulator.live,
      deletedLocationsById: accumulator.deleted,
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
    (int?, bool, DateTime) options, {
    Set<String> tombstonedLocationIds = const <String>{},
    Set<String> tombstonedLabelIds = const <String>{},
    Set<String>? validLabelIds,
    Map<String, TdfLabel> postCascadeLabelsById = const <String, TdfLabel>{},
  }) {
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
      if (_reconcileSingleTask(
        id,
        pair,
        context,
        accumulator,
        tombstonedLocationIds: tombstonedLocationIds,
        tombstonedLabelIds: tombstonedLabelIds,
        validLabelIds: validLabelIds,
        postCascadeLabelsById: postCascadeLabelsById,
      )) {
        retired = true;
      }
    }
    return TaskReconciliationOutcome(
      liveTasks: accumulator.live,
      deletedTasksById: accumulator.deleted,
      conflictedIds: accumulator.conflicted,
      ambiguousIds: accumulator.ambiguous,
      retiredByUndelete: retired,
    );
  }

  /// Strips deleted labels from [tasks] (advancing affected tasks' `modified` timestamp),
  /// clears `isPriority` and records queue eviction when a task loses its last `scoped` label (`spec/TDF_SPEC_0.6.0.md` Section 6.7.8),
  /// and validates that no unknown label references remain.
  static List<TaskItem> stripDeletedLabelsAndValidateReferences(
    List<TaskItem> tasks,
    Set<String> validIds,
    Map<String, TdfDeletedLabelRecord> deletedById,
    List<TdfLabel>? baselineLabels, {
    Set<String> knownScopedLabelIds = const <String>{},
    Set<String>? evictedFromQueueOut,
    (TaskBoard, TaskBoard, TaskBoard?)? boards,
  }) {
    final baseIds = <String>{
      if (baselineLabels != null)
        for (final label in baselineLabels) label.id,
    };
    final scopedIds = <String>{
      ...knownScopedLabelIds,
      if (baselineLabels != null)
        for (final label in baselineLabels)
          if (label.isScoped) label.id,
    };
    final primaryMap = boards != null
        ? _indexById(boards.$1.allTasks, (task) => task.id)
        : const <String, TaskItem>{};
    final secondaryMap = boards != null
        ? _indexById(boards.$2.allTasks, (task) => task.id)
        : const <String, TaskItem>{};
    final baselineMap = boards?.$3 != null
        ? _indexById(
            boards?.$3?.allTasks ?? const <TaskItem>[],
            (task) => task.id,
          )
        : const <String, TaskItem>{};
    return <TaskItem>[
      for (final task in tasks)
        _stripDeletedLabelsFromSingleTask(
          task,
          validIds,
          deletedById,
          baseIds,
          scopedIds,
          evictedFromQueueOut,
          sourceVariants: (
            primaryMap[task.id],
            secondaryMap[task.id],
            baselineMap[task.id],
          ),
        ),
    ];
  }

  /// Strips deleted locations from [labels] (advancing affected labels' `modified` timestamp)
  /// and validates that no unknown location references remain per Sections 6.7.8 and 6.8.1.
  static List<TdfLabel> stripDeletedLocationsFromLabelsAndValidate(
    List<TdfLabel> labels,
    Set<String> validLocationIds,
    Map<String, TdfDeletedLocationRecord> deletedLocationsById,
    List<TdfLocation>? baselineLocations,
  ) {
    final baseIds = <String>{
      if (baselineLocations != null)
        for (final location in baselineLocations) location.id,
    };
    return <TdfLabel>[
      for (final label in labels)
        _stripDeletedLocationsFromSingleLabel(
          label,
          validLocationIds,
          deletedLocationsById,
          baseIds,
        ),
    ];
  }

  /// Strips deleted locations from [tasks] (inserting `condition location any` when a live assigned label still carries a location rule),
  /// advances affected tasks' `modified` timestamp, and validates that no unknown location references remain per Sections 6.7.8 and 6.8.1.
  static List<TaskItem> stripDeletedLocationsFromTasksAndValidate(
    List<TaskItem> tasks,
    Set<String> validLocationIds,
    Map<String, TdfDeletedLocationRecord> deletedLocationsById,
    List<TdfLocation>? baselineLocations,
    Map<String, TdfLabel> postCascadeLabelsById,
  ) {
    final baseIds = <String>{
      if (baselineLocations != null)
        for (final location in baselineLocations) location.id,
    };
    return <TaskItem>[
      for (final task in tasks)
        _stripDeletedLocationsFromSingleTask(
          task,
          validLocationIds,
          deletedLocationsById,
          baseIds,
          postCascadeLabelsById,
        ),
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

  /// Appends elements in [current] that are absent from [baseline] into [target].
  static void _collectAddedStrings(
    Iterable<String> current,
    List<String> baseline,
    Set<String> target,
  ) {
    for (final id in current) {
      if (!baseline.contains(id)) {
        target.add(id);
      }
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

  /// Extracts all referenced `<location-id>` tokens from [conditions].
  static List<String> _extractLocationIds(List<TaskCondition> conditions) {
    final ids = <String>[];
    for (final rule in conditions) {
      if (rule is LocationTaskCondition && rule.locationIds.isNotEmpty) {
        ids.addAll(rule.locationIds);
      }
    }
    return ids;
  }

  /// Filters [locationIds] against [validLocationIds], [deletedLocationsById], and [baselineLocationSet].
  static ({List<String> retainedIds, bool strippedAny, DateTime? latestAt})
  _filterLocationIdsForEntity({
    required String entityKind,
    required String entityId,
    required List<String> locationIds,
    required Set<String> validLocationIds,
    required Map<String, TdfDeletedLocationRecord> deletedLocationsById,
    required Set<String> baselineLocationSet,
  }) {
    final retained = <String>[];
    var stripped = false;
    DateTime? latestAt;

    for (final locId in locationIds) {
      if (validLocationIds.contains(locId)) {
        retained.add(locId);
        continue;
      }
      final deletedRecord = deletedLocationsById[locId];
      if (deletedRecord != null || baselineLocationSet.contains(locId)) {
        stripped = true;
        latestAt = _maxNullableDate(latestAt, deletedRecord?.deletedAt);
        continue;
      }
      throw TdfException(
        kind: TdfErrorKind.unknownLocationReference,
        line: 1,
        message:
            'Merged $entityKind "$entityId" references undeclared location "$locId".',
      );
    }
    return (retainedIds: retained, strippedAny: stripped, latestAt: latestAt);
  }

  /// Computes the post-cascade [TaskItem] and its deterministic Section 6.7.6 revision after stripping deleted labels.
  static TaskItem _finalizePostLabelCascadeTask(
    TaskItem task, {
    required List<String> retained,
    required bool nextPriority,
    required DateTime? latestLabelDeletion,
    required (TaskItem?, TaskItem?, TaskItem?) sourceVariants,
  }) {
    final candidate = task.copyWith(
      labelIds: retained,
      isPriority: nextPriority,
    );
    final (primaryTask, secondaryTask, baselineTask) = sourceVariants;
    if (primaryTask != null && secondaryTask != null) {
      var greatest =
          TdfPayloadComparison.compareTaskVersions(
                primaryTask,
                secondaryTask,
              ) >=
              0
          ? primaryTask
          : secondaryTask;
      if (baselineTask != null &&
          TdfPayloadComparison.compareTaskVersions(baselineTask, greatest) >
              0) {
        greatest = baselineTask;
      }
      final deletionNotNewer =
          latestLabelDeletion == null ||
          !latestLabelDeletion.isAfter(greatest.effectiveModifiedAt);
      if (deletionNotNewer &&
          greatest.completions == candidate.completions &&
          TdfPayloadComparison.compareTaskPayloads(greatest, candidate) == 0) {
        return greatest;
      }
      var maxObserved = _laterDate(
        primaryTask.effectiveModifiedAt,
        secondaryTask.effectiveModifiedAt,
      );
      maxObserved = _laterDate(maxObserved, baselineTask?.effectiveModifiedAt);
      maxObserved = _laterDate(maxObserved, latestLabelDeletion);
      return candidate.copyWith(
        modifiedAt: maxObserved.add(const Duration(seconds: 1)),
      );
    }
    final baseModified = _laterDate(
      task.effectiveModifiedAt,
      latestLabelDeletion,
    );
    return candidate.copyWith(
      modifiedAt: baseModified.add(const Duration(seconds: 1)),
    );
  }

  /// Returns whether any label in [labelIds] has a post-cascade `LocationTaskCondition` in [postCascadeLabelsById].
  static bool _hasLiveLabelLocationRule(
    List<String> labelIds,
    Map<String, TdfLabel> postCascadeLabelsById,
  ) {
    for (final labelId in labelIds) {
      final label = postCascadeLabelsById[labelId];
      if (label != null && _extractLocationIds(label.conditions).isNotEmpty) {
        return true;
      }
    }
    return false;
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

  /// Returns whether [location] is identical to [baseLocation] in payload and effective revision.
  static bool _isLocationUnchangedFromBaseline(
    TdfLocation location,
    TdfLocation baseLocation,
  ) =>
      location.effectiveModifiedAt == baseLocation.effectiveModifiedAt &&
      TdfPayloadComparison.compareLocationPayloads(location, baseLocation) == 0;

  /// Returns whether [task] is identical to [baseTask] in payload, completions, and effective revision.
  static bool _isTaskUnchangedFromBaseline(TaskItem task, TaskItem baseTask) =>
      task.completions == baseTask.completions &&
      task.effectiveModifiedAt == baseTask.effectiveModifiedAt &&
      TdfPayloadComparison.compareTaskPayloads(task, baseTask) == 0;

  /// Returns the later of [left] and optional [right].
  static DateTime _laterDate(DateTime left, DateTime? right) =>
      (right != null && right.isAfter(left)) ? right : left;

  /// Returns the maximum of three integers.
  static int _max3Int(int a, int b, int c) {
    final ab = a >= b ? a : b;
    return ab >= c ? ab : c;
  }

  /// Returns the later of two nullable [DateTime] values.
  static DateTime? _maxNullableDate(DateTime? left, DateTime? right) {
    if (left == null) return right;
    if (right == null) return left;
    return right.isAfter(left) ? right : left;
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
    _LabelAccumulator accumulator, {
    required Set<String> tombstonedLocationIds,
    required Set<String> newlyReferencedLabelIds,
  }) {
    final (primaryLabel, secondaryLabel, baselineLabel) = entities;
    if (primaryLabel != null && secondaryLabel != null) {
      final mergedLabel = TdfPayloadComparison.mergeLabelWithBaseline(
        local: primaryLabel,
        incoming: secondaryLabel,
        baseline: baselineLabel,
        tombstonedLocationIds: tombstonedLocationIds,
      );
      final winner = identical(mergedLabel, primaryLabel)
          ? 'primary'
          : (identical(mergedLabel, secondaryLabel) ? 'secondary' : 'merged');
      AppLogger.event(
        LogLevel.debug,
        LogTag.sync,
        'sync.reconcile.label',
        fields: <String, Object?>{
          'id': id,
          'winner': winner,
          'primary_rev': primaryLabel.effectiveModifiedAt.toIso8601String(),
          'secondary_rev': secondaryLabel.effectiveModifiedAt.toIso8601String(),
        },
      );
      accumulator.live.add(mergedLabel);
      return false;
    }

    final surviving = primaryLabel ?? secondaryLabel;
    if (surviving == null) return false;
    final unchanged =
        baselineLabel != null &&
        _isLabelUnchangedFromBaseline(surviving, baselineLabel) &&
        !newlyReferencedLabelIds.contains(id);

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

  /// Reconciles a single location [id] and returns whether an explicit `Undelete` retired a deletion record.
  static bool _reconcileSingleLocation(
    String id,
    (TdfLocation?, TdfLocation?, TdfLocation?) entities,
    _ReconcileContext context,
    _LocationAccumulator accumulator, {
    required Set<String> newlyReferencedLocationIds,
  }) {
    final (primaryLoc, secondaryLoc, baselineLoc) = entities;
    if (primaryLoc != null && secondaryLoc != null) {
      final mergedLoc = TdfPayloadComparison.mergeLocationWithBaseline(
        local: primaryLoc,
        incoming: secondaryLoc,
        baseline: baselineLoc,
      );
      final winner = identical(mergedLoc, primaryLoc)
          ? 'primary'
          : (identical(mergedLoc, secondaryLoc) ? 'secondary' : 'merged');
      AppLogger.event(
        LogLevel.debug,
        LogTag.sync,
        'sync.reconcile.location',
        fields: <String, Object?>{
          'id': id,
          'winner': winner,
          'primary_rev': primaryLoc.effectiveModifiedAt.toIso8601String(),
          'secondary_rev': secondaryLoc.effectiveModifiedAt.toIso8601String(),
        },
      );
      accumulator.live.add(mergedLoc);
      return false;
    }

    final surviving = primaryLoc ?? secondaryLoc;
    if (surviving == null) return false;
    final unchanged =
        baselineLoc != null &&
        _isLocationUnchangedFromBaseline(surviving, baselineLoc) &&
        !newlyReferencedLocationIds.contains(id);

    final TdfDeletedLocationRecord conflictRecord;
    if (accumulator.deleted[id] case final existingDeleted?) {
      if (unchanged) return false;
      conflictRecord = existingDeleted;
    } else if (baselineLoc != null) {
      if (context.genAdvanced) {
        if (!unchanged) accumulator.ambiguous.add(id);
        return false;
      }
      final synthAt = TaskItem.nextModifiedTimestamp(
        context.now,
        baselineLoc.effectiveModifiedAt,
      );
      conflictRecord = TdfDeletedLocationRecord(
        locationId: id,
        deletedAt: synthAt,
      );
      if (unchanged) {
        accumulator.deleted[id] = conflictRecord;
        return false;
      }
    } else {
      if (primaryLoc != null ? context.primaryAmb : context.secondaryAmb) {
        accumulator.ambiguous.add(id);
      } else {
        accumulator.live.add(surviving);
      }
      return false;
    }
    final conflict = (surviving, baselineLoc, conflictRecord);
    return _resolveLocationDeletionConflict(conflict, context, accumulator);
  }

  /// Reconciles a single task [id] and returns whether an explicit `Undelete` retired a deletion record.
  static bool _reconcileSingleTask(
    String id,
    (TaskItem?, TaskItem?, TaskItem?) entities,
    _ReconcileContext context,
    _TaskAccumulator accumulator, {
    required Set<String> tombstonedLocationIds,
    required Set<String> tombstonedLabelIds,
    required Set<String>? validLabelIds,
    required Map<String, TdfLabel> postCascadeLabelsById,
  }) {
    final (primaryTask, secondaryTask, baselineTask) = entities;
    if (primaryTask != null && secondaryTask != null) {
      final mergedTask = TdfPayloadComparison.mergeTaskWithBaseline(
        local: primaryTask,
        incoming: secondaryTask,
        baseline: baselineTask,
        tombstonedLocationIds: tombstonedLocationIds,
        tombstonedLabelIds: tombstonedLabelIds,
        validLabelIds: validLabelIds,
        postCascadeLabelsById: postCascadeLabelsById,
      );
      final winner = identical(mergedTask, primaryTask)
          ? 'primary'
          : (identical(mergedTask, secondaryTask) ? 'secondary' : 'merged');
      AppLogger.event(
        LogLevel.debug,
        LogTag.sync,
        'sync.reconcile.task',
        fields: <String, Object?>{
          'id': id,
          'winner': winner,
          'primary_rev': primaryTask.effectiveModifiedAt.toIso8601String(),
          'secondary_rev': secondaryTask.effectiveModifiedAt.toIso8601String(),
        },
      );
      accumulator.live.add(mergedTask);
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
  static bool _resolveLocationDeletionConflict(
    (TdfLocation, TdfLocation?, TdfDeletedLocationRecord) conflict,
    _ReconcileContext context,
    _LocationAccumulator accumulator,
  ) {
    final (surviving, baselineLoc, deletedRecord) = conflict;
    final id = surviving.id;
    final resolution = context.resolutions[id];
    if (resolution == null) {
      accumulator.conflicted.add(id);
      return false;
    }
    final revisions = (
      surviving.effectiveModifiedAt,
      deletedRecord.deletedAt,
      baselineLoc?.effectiveModifiedAt,
    );
    final revision = _computeDecisionRevision(revisions, context.now);
    switch (resolution) {
      case TdfDeletionResolution.delete:
        accumulator.deleted[id] = TdfDeletedLocationRecord(
          locationId: id,
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
    Set<String> scopedLabelSet,
    Set<String>? evictedFromQueueOut, {
    (TaskItem?, TaskItem?, TaskItem?) sourceVariants = (null, null, null),
  }) {
    if (task.labelIds.isEmpty) return task;
    final retained = <String>[];
    DateTime? latestLabelDeletion;
    var strippedAny = false;
    var allBeforeWereScoped = true;

    for (final labelId in task.labelIds) {
      if (!scopedLabelSet.contains(labelId)) {
        allBeforeWereScoped = false;
      }
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
    final lostLastScopedLabel = retained.isEmpty && allBeforeWereScoped;
    if (lostLastScopedLabel && evictedFromQueueOut != null) {
      evictedFromQueueOut.add(task.id);
    }
    return _finalizePostLabelCascadeTask(
      task,
      retained: retained,
      nextPriority: lostLastScopedLabel ? false : task.isPriority,
      latestLabelDeletion: latestLabelDeletion,
      sourceVariants: sourceVariants,
    );
  }

  /// Strips deleted locations from a single [label] and validates remaining location references.
  static TdfLabel _stripDeletedLocationsFromSingleLabel(
    TdfLabel label,
    Set<String> validLocationIds,
    Map<String, TdfDeletedLocationRecord> deletedLocationsById,
    Set<String> baselineLocationSet,
  ) {
    if (label.conditions.isEmpty) return label;
    final updatedConditions = <TaskCondition>[];
    DateTime? latestDeletion;
    var strippedAny = false;

    for (final rule in label.conditions) {
      if (rule is! LocationTaskCondition || rule.locationIds.isEmpty) {
        updatedConditions.add(rule);
        continue;
      }
      final filtered = _filterLocationIdsForEntity(
        entityKind: 'label',
        entityId: label.id,
        locationIds: rule.locationIds,
        validLocationIds: validLocationIds,
        deletedLocationsById: deletedLocationsById,
        baselineLocationSet: baselineLocationSet,
      );
      if (filtered.strippedAny) {
        strippedAny = true;
        latestDeletion = _maxNullableDate(latestDeletion, filtered.latestAt);
      }
      if (filtered.retainedIds.isNotEmpty) {
        updatedConditions.add(
          LocationTaskCondition(locationIds: filtered.retainedIds),
        );
      }
    }

    if (!strippedAny) return label;
    var baseModified = label.effectiveModifiedAt;
    if (latestDeletion != null && latestDeletion.isAfter(baseModified)) {
      baseModified = latestDeletion;
    }
    return label.copyWith(
      conditions: updatedConditions,
      modifiedAt: baseModified.add(const Duration(seconds: 1)),
    );
  }

  /// Strips deleted locations from a single [task] and validates remaining location references.
  static TaskItem _stripDeletedLocationsFromSingleTask(
    TaskItem task,
    Set<String> validLocationIds,
    Map<String, TdfDeletedLocationRecord> deletedLocationsById,
    Set<String> baselineLocationSet,
    Map<String, TdfLabel> postCascadeLabelsById,
  ) {
    if (task.conditions.isEmpty) return task;
    final updatedConditions = <TaskCondition>[];
    DateTime? latestDeletion;
    var strippedAny = false;

    for (final rule in task.conditions) {
      if (rule is! LocationTaskCondition || rule.locationIds.isEmpty) {
        updatedConditions.add(rule);
        continue;
      }
      final filtered = _filterLocationIdsForEntity(
        entityKind: 'task',
        entityId: task.id,
        locationIds: rule.locationIds,
        validLocationIds: validLocationIds,
        deletedLocationsById: deletedLocationsById,
        baselineLocationSet: baselineLocationSet,
      );
      if (filtered.strippedAny) {
        strippedAny = true;
        latestDeletion = _maxNullableDate(latestDeletion, filtered.latestAt);
      }
      if (filtered.retainedIds.isNotEmpty) {
        updatedConditions.add(
          LocationTaskCondition(locationIds: filtered.retainedIds),
        );
      } else if (_hasLiveLabelLocationRule(
        task.labelIds,
        postCascadeLabelsById,
      )) {
        updatedConditions.add(
          const GroupResetTaskCondition(targetGroup: ConditionGroup.location),
        );
      }
    }

    if (!strippedAny) return task;
    var baseModified = task.effectiveModifiedAt;
    if (latestDeletion != null && latestDeletion.isAfter(baseModified)) {
      baseModified = latestDeletion;
    }
    return task.copyWith(
      conditions: updatedConditions,
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

/// Mutable accumulator used while reconciling locations across two boards.
typedef _LocationAccumulator = ({
  List<TdfLocation> live,
  Map<String, TdfDeletedLocationRecord> deleted,
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
