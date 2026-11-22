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
import 'tdf_entity_merger.dart';
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
    this.discardedIds = const <String>{},
    this.explicitlyDeletedIds = const <String>{},
  });

  /// Label IDs requiring user recovery after deletion history expiry.
  final List<String> ambiguousIds;

  /// Label IDs with unresolved deletion vs. modification conflicts.
  final List<String> conflictedIds;

  /// Active label deletion records keyed by label ID.
  final Map<String, TdfDeletedLabelRecord> deletedLabelsById;

  /// Stale-side label IDs discarded during generation refresh or explicit `discard` recovery.
  final Set<String> discardedIds;

  /// Label IDs resolved via explicit `Delete` during `DeletionConflict` resolution.
  final Set<String> explicitlyDeletedIds;

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
    this.discardedIds = const <String>{},
    this.explicitlyDeletedIds = const <String>{},
  });

  /// Location IDs requiring user recovery after deletion history expiry.
  final List<String> ambiguousIds;

  /// Location IDs with unresolved deletion vs. modification conflicts.
  final List<String> conflictedIds;

  /// Active location deletion records keyed by location ID.
  final Map<String, TdfDeletedLocationRecord> deletedLocationsById;

  /// Stale-side location IDs discarded during generation refresh or explicit `discard` recovery.
  final Set<String> discardedIds;

  /// Location IDs resolved via explicit `Delete` during `DeletionConflict` resolution.
  final Set<String> explicitlyDeletedIds;

  /// Surviving reconciled live locations.
  final List<TdfLocation> liveLocations;

  /// Whether at least one deletion record was retired by an explicit undelete resolution.
  final bool retiredByUndelete;
}

/// Prebuilt entity lookup maps shared across merge reconciliation phases to eliminate redundant $O(N)$ re-indexing.
@immutable
class SyncBoardIndices {
  /// Creates a [SyncBoardIndices] snapshot with prebuilt entity maps.
  const SyncBoardIndices._({
    required this.primaryTasks,
    required this.secondaryTasks,
    required this.baselineTasks,
    required this.primaryLabels,
    required this.secondaryLabels,
    required this.baselineLabels,
    required this.primaryLocations,
    required this.secondaryLocations,
    required this.baselineLocations,
  });

  /// Builds lookup maps for tasks, labels, and locations across [primary], [secondary], and optional [baseline].
  factory SyncBoardIndices.fromBoards(
    TaskBoard primary,
    TaskBoard secondary,
    TaskBoard? baseline,
  ) => SyncBoardIndices._(
    primaryTasks: <String, TaskItem>{
      for (final task in primary.allTasks) task.id: task,
    },
    secondaryTasks: <String, TaskItem>{
      for (final task in secondary.allTasks) task.id: task,
    },
    baselineTasks: baseline == null
        ? null
        : <String, TaskItem>{
            for (final task in baseline.allTasks) task.id: task,
          },
    primaryLabels: <String, TdfLabel>{
      for (final label in primary.labels) label.id: label,
    },
    secondaryLabels: <String, TdfLabel>{
      for (final label in secondary.labels) label.id: label,
    },
    baselineLabels: baseline == null
        ? null
        : <String, TdfLabel>{
            for (final label in baseline.labels) label.id: label,
          },
    primaryLocations: <String, TdfLocation>{
      for (final location in primary.locations) location.id: location,
    },
    secondaryLocations: <String, TdfLocation>{
      for (final location in secondary.locations) location.id: location,
    },
    baselineLocations: baseline == null
        ? null
        : <String, TdfLocation>{
            for (final location in baseline.locations) location.id: location,
          },
  );

  /// Optional baseline labels indexed by ID.
  final Map<String, TdfLabel>? baselineLabels;

  /// Optional baseline locations indexed by ID.
  final Map<String, TdfLocation>? baselineLocations;

  /// Optional baseline tasks indexed by ID.
  final Map<String, TaskItem>? baselineTasks;

  /// Primary board labels indexed by ID.
  final Map<String, TdfLabel> primaryLabels;

  /// Primary board locations indexed by ID.
  final Map<String, TdfLocation> primaryLocations;

  /// Primary board tasks indexed by ID.
  final Map<String, TaskItem> primaryTasks;

  /// Secondary board labels indexed by ID.
  final Map<String, TdfLabel> secondaryLabels;

  /// Secondary board locations indexed by ID.
  final Map<String, TdfLocation> secondaryLocations;

  /// Secondary board tasks indexed by ID.
  final Map<String, TaskItem> secondaryTasks;
}

/// Stateless per-entity three-way location, label, and task reconciliation engine for `TaskBoardSync`.
@immutable
class TaskBoardReconciler {
  /// Prevents instantiation of this stateless helper class.
  const TaskBoardReconciler._();

  static final _EntityReconciliationAdapter<TdfLabel, TdfDeletedLabelRecord>
  _labelAdapter = _EntityReconciliationAdapter<TdfLabel, TdfDeletedLabelRecord>(
    idOf: (label) => label.id,
    effectiveModifiedAtOf: (label) => label.effectiveModifiedAt,
    deletedAtOf: (record) => record.deletedAt,
    payloadSignatureOf: TdfPayloadComparison.labelPayloadSignature,
    makeBaselineTombstone: (id, deletedAt, _) =>
        TdfDeletedLabelRecord(labelId: id, deletedAt: deletedAt),
    makeResolvedDeleteRecord: (id, revision, _, _, _) =>
        TdfDeletedLabelRecord(labelId: id, deletedAt: revision),
    buildUndeletedEntity: (surviving, _, _, revision) =>
        surviving.copyWith(modifiedAt: revision),
  );

  static final _EntityReconciliationAdapter<
    TdfLocation,
    TdfDeletedLocationRecord
  >
  _locationAdapter =
      _EntityReconciliationAdapter<TdfLocation, TdfDeletedLocationRecord>(
        idOf: (location) => location.id,
        effectiveModifiedAtOf: (location) => location.effectiveModifiedAt,
        deletedAtOf: (record) => record.deletedAt,
        payloadSignatureOf: TdfPayloadComparison.locationPayloadSignature,
        makeBaselineTombstone: (id, deletedAt, _) =>
            TdfDeletedLocationRecord(locationId: id, deletedAt: deletedAt),
        makeResolvedDeleteRecord: (id, revision, _, _, _) =>
            TdfDeletedLocationRecord(locationId: id, deletedAt: revision),
        buildUndeletedEntity: (surviving, _, _, revision) =>
            surviving.copyWith(modifiedAt: revision),
      );

  static final _EntityReconciliationAdapter<TaskItem, TdfDeletedTaskRecord>
  _taskAdapter = _EntityReconciliationAdapter<TaskItem, TdfDeletedTaskRecord>(
    idOf: (task) => task.id,
    effectiveModifiedAtOf: (task) => task.effectiveModifiedAt,
    deletedAtOf: (record) => record.deletedAt,
    payloadSignatureOf: TdfPayloadComparison.taskPayloadSignature,
    makeBaselineTombstone: (id, deletedAt, baselineTask) =>
        TdfDeletedTaskRecord(
          taskId: id,
          deletedAt: deletedAt,
          completionsCheckpoint: baselineTask.completions,
        ),
    makeResolvedDeleteRecord: (id, revision, surviving, baseline, existing) =>
        TdfDeletedTaskRecord(
          taskId: id,
          deletedAt: revision,
          completionsCheckpoint: _max3Int(
            surviving.completions,
            baseline?.completions ?? 0,
            existing.completionsCheckpoint,
          ),
        ),
    buildUndeletedEntity: (surviving, baseline, deletedRecord, revision) =>
        surviving.copyWith(
          completions: _max3Int(
            surviving.completions,
            baseline?.completions ?? 0,
            deletedRecord.completionsCheckpoint,
          ),
          modifiedAt: revision,
        ),
    onUnchangedExistingTombstone: (id, existing, surviving, baseline, deleted) {
      final maxComp = _max3Int(
        existing.completionsCheckpoint,
        surviving.completions,
        baseline.completions,
      );
      deleted[id] = TdfDeletedTaskRecord(
        taskId: id,
        deletedAt: existing.deletedAt,
        completionsCheckpoint: maxComp,
      );
    },
  );

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
        message: 'Ambiguous entities require user recovery after deletion history expiry.',
      );
    }
  }

  /// Computes label IDs resolved for explicit `Delete` or recovery `discard` so they do not trigger newly-introduced location reference conflicts (`TDF-DEL-002`).
  static Set<String> computeExplicitlyDeletedLabelIds(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    Map<String, TdfDeletedLabelRecord> initialDeletedLabels,
    (int?, bool, DateTime) options, {
    Map<String, TdfDeletionResolution> resolutions = const {},
    Map<String, TdfBoundDeletionDecision> boundDecisions = const {},
    Map<String, TdfRecoveryResolution> recoveryResolutions = const {},
    Set<String> freshlyRecoveredIds = const <String>{},
    SyncBoardIndices? indices,
  }) => _computeExplicitlyDeletedIds<TdfLabel, TdfDeletedLabelRecord>(
    adapter: _labelAdapter,
    maps: _resolveBoardMaps<TdfLabel>(
      boards,
      cachedPrimary: indices?.primaryLabels,
      cachedSecondary: indices?.secondaryLabels,
      cachedBaseline: indices?.baselineLabels,
      hasIndices: indices != null,
      extract: (board) => board.labels,
      idOf: (label) => label.id,
    ),
    initialDeleted: initialDeletedLabels,
    context: _reconcileContext(boards, options),
    resolutions: resolutions,
    boundDecisions: boundDecisions,
    recoveryResolutions: recoveryResolutions,
    freshlyRecoveredIds: freshlyRecoveredIds,
  );

  /// Computes task IDs resolved for explicit `Delete` or recovery `discard` so they do not trigger newly-introduced label or location reference conflicts (`TDF-DEL-002`).
  static Set<String> computeExplicitlyDeletedTaskIds(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    Map<String, TdfDeletedTaskRecord> initialDeletedTasks,
    (int?, bool, DateTime) options, {
    Map<String, TdfDeletionResolution> resolutions = const {},
    Map<String, TdfBoundDeletionDecision> boundDecisions = const {},
    Map<String, TdfRecoveryResolution> recoveryResolutions = const {},
    Set<String> freshlyRecoveredIds = const <String>{},
    SyncBoardIndices? indices,
  }) => _computeExplicitlyDeletedIds<TaskItem, TdfDeletedTaskRecord>(
    adapter: _taskAdapter,
    maps: _resolveBoardMaps<TaskItem>(
      boards,
      cachedPrimary: indices?.primaryTasks,
      cachedSecondary: indices?.secondaryTasks,
      cachedBaseline: indices?.baselineTasks,
      hasIndices: indices != null,
      extract: (board) => board.allTasks,
      idOf: (task) => task.id,
    ),
    initialDeleted: initialDeletedTasks,
    context: _reconcileContext(boards, options),
    resolutions: resolutions,
    boundDecisions: boundDecisions,
    recoveryResolutions: recoveryResolutions,
    freshlyRecoveredIds: freshlyRecoveredIds,
  );

  /// Computes newly introduced label references $A_L(T) \cup A_R(T)$ across live and conflict-retained tasks (`TDF-DEL-002`).
  static Set<String> computeNewlyReferencedLabelIds(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    Map<String, TdfDeletedTaskRecord> initialDeletedTasks, {
    Set<String> explicitlyDeletedTaskIds = const <String>{},
    SyncBoardIndices? indices,
  }) {
    final (primary, secondary, baseline) = boards;
    if (baseline == null) {
      return const <String>{};
    }
    final baseTaskMap =
        indices?.baselineTasks ??
        _indexById(baseline.allTasks, (task) => task.id);
    final newlyReferenced = <String>{};
    for (final task in <TaskItem>[...primary.allTasks, ...secondary.allTasks]) {
      if (explicitlyDeletedTaskIds.contains(task.id)) {
        continue;
      }
      final baseTask = baseTaskMap[task.id];
      if (baseTask != null) {
        _collectAddedStrings(task.labelIds, baseTask.labelIds, newlyReferenced);
      } else {
        newlyReferenced.addAll(task.labelIds);
      }
    }
    return newlyReferenced;
  }

  /// Computes newly introduced location references $A^{\text{loc}}_L(E) \cup A^{\text{loc}}_R(E)$ across live and conflict-retained tasks and labels (`TDF-DEL-002`).
  static Set<String> computeNewlyReferencedLocationIds(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    Map<String, TdfDeletedTaskRecord> initialDeletedTasks,
    Map<String, TdfDeletedLabelRecord> initialDeletedLabels, {
    Set<String> explicitlyDeletedTaskIds = const <String>{},
    Set<String> explicitlyDeletedLabelIds = const <String>{},
    SyncBoardIndices? indices,
  }) {
    final (primary, secondary, baseline) = boards;
    if (baseline == null) {
      return const <String>{};
    }
    final baseTaskMap =
        indices?.baselineTasks ??
        _indexById(baseline.allTasks, (task) => task.id);
    final baseLabelMap =
        indices?.baselineLabels ??
        _indexById(baseline.labels, (label) => label.id);
    final newlyReferenced = <String>{};
    _collectNewlyReferencedConditionLocations<TaskItem>(
      entities: <TaskItem>[...primary.allTasks, ...secondary.allTasks],
      excludedIds: explicitlyDeletedTaskIds,
      baselineById: baseTaskMap,
      idOf: (task) => task.id,
      conditionsOf: (task) => task.conditions,
      target: newlyReferenced,
    );
    _collectNewlyReferencedConditionLocations<TdfLabel>(
      entities: <TdfLabel>[...primary.labels, ...secondary.labels],
      excludedIds: explicitlyDeletedLabelIds,
      baselineById: baseLabelMap,
      idOf: (label) => label.id,
      conditionsOf: (label) => label.conditions,
      target: newlyReferenced,
    );
    return newlyReferenced;
  }

  /// Reconciles all `label` blocks across [boards], [initialDeleted], [resolutions], and [options].
  static LabelReconciliationOutcome reconcileLabels(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    Map<String, TdfDeletedLabelRecord> initialDeleted,
    Map<String, TdfDeletionResolution> resolutions,
    (int?, bool, DateTime) options, {
    Map<String, TdfBoundDeletionDecision> boundDecisions = const {},
    Map<String, TdfRecoveryResolution> recoveryResolutions = const {},
    Set<String> freshlyRecoveredIds = const <String>{},
    Set<String> tombstonedLocationIds = const <String>{},
    Set<String> newlyReferencedLabelIds = const <String>{},
    SyncBoardIndices? indices,
  }) {
    final result = _reconcileSimpleEntities<TdfLabel, TdfDeletedLabelRecord>(
      adapter: _labelAdapter,
      maps: _resolveBoardMaps<TdfLabel>(
        boards,
        cachedPrimary: indices?.primaryLabels,
        cachedSecondary: indices?.secondaryLabels,
        cachedBaseline: indices?.baselineLabels,
        hasIndices: indices != null,
        extract: (board) => board.labels,
        idOf: (label) => label.id,
      ),
      initialDeleted: initialDeleted,
      context: _reconcileContext(boards, options),
      resolutions: resolutions,
      boundDecisions: boundDecisions,
      recoveryResolutions: recoveryResolutions,
      freshlyRecoveredIds: freshlyRecoveredIds,
      logEventName: 'sync.reconcile.label',
      mergeTwoSided: (local, incoming, baseline) =>
          TdfEntityMerger.mergeLabelWithBaseline(
            local: local,
            incoming: incoming,
            baseline: baseline,
            tombstonedLocationIds: tombstonedLocationIds,
          ),
      isUnchangedFromBaseline: (id, surviving, baseLabel) =>
          surviving.effectiveModifiedAt == baseLabel.effectiveModifiedAt &&
          TdfPayloadComparison.compareLabelPayloads(surviving, baseLabel) ==
              0 &&
          !newlyReferencedLabelIds.contains(id),
    );
    return LabelReconciliationOutcome(
      liveLabels: result.accumulator.live,
      deletedLabelsById: result.accumulator.deleted,
      conflictedIds: result.accumulator.conflicted,
      ambiguousIds: result.accumulator.ambiguous,
      retiredByUndelete: result.retiredByUndelete,
      discardedIds: result.accumulator.discarded,
      explicitlyDeletedIds: result.accumulator.explicitlyDeleted,
    );
  }

  /// Reconciles all `location` blocks across [boards], [initialDeleted], [resolutions], and [options].
  static LocationReconciliationOutcome reconcileLocations(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    Map<String, TdfDeletedLocationRecord> initialDeleted,
    Map<String, TdfDeletionResolution> resolutions,
    (int?, bool, DateTime) options, {
    Map<String, TdfBoundDeletionDecision> boundDecisions = const {},
    Map<String, TdfRecoveryResolution> recoveryResolutions = const {},
    Set<String> freshlyRecoveredIds = const <String>{},
    Set<String> newlyReferencedLocationIds = const <String>{},
    SyncBoardIndices? indices,
  }) {
    final result =
        _reconcileSimpleEntities<TdfLocation, TdfDeletedLocationRecord>(
          adapter: _locationAdapter,
          maps: _resolveBoardMaps<TdfLocation>(
            boards,
            cachedPrimary: indices?.primaryLocations,
            cachedSecondary: indices?.secondaryLocations,
            cachedBaseline: indices?.baselineLocations,
            hasIndices: indices != null,
            extract: (board) => board.locations,
            idOf: (location) => location.id,
          ),
          initialDeleted: initialDeleted,
          context: _reconcileContext(boards, options),
          resolutions: resolutions,
          boundDecisions: boundDecisions,
          recoveryResolutions: recoveryResolutions,
          freshlyRecoveredIds: freshlyRecoveredIds,
          logEventName: 'sync.reconcile.location',
          mergeTwoSided: (local, incoming, baseline) =>
              TdfEntityMerger.mergeLocationWithBaseline(
                local: local,
                incoming: incoming,
                baseline: baseline,
              ),
          isUnchangedFromBaseline: (id, surviving, baseLocation) =>
              surviving.effectiveModifiedAt ==
                  baseLocation.effectiveModifiedAt &&
              TdfPayloadComparison.compareLocationPayloads(
                    surviving,
                    baseLocation,
                  ) ==
                  0 &&
              !newlyReferencedLocationIds.contains(id),
        );
    return LocationReconciliationOutcome(
      liveLocations: result.accumulator.live,
      deletedLocationsById: result.accumulator.deleted,
      conflictedIds: result.accumulator.conflicted,
      ambiguousIds: result.accumulator.ambiguous,
      retiredByUndelete: result.retiredByUndelete,
      discardedIds: result.accumulator.discarded,
      explicitlyDeletedIds: result.accumulator.explicitlyDeleted,
    );
  }

  /// Reconciles all `task` blocks across [boards], [initialDeleted], [resolutions], and [options].
  static TaskReconciliationOutcome reconcileTasks(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    Map<String, TdfDeletedTaskRecord> initialDeleted,
    Map<String, TdfDeletionResolution> resolutions,
    (int?, bool, DateTime) options, {
    Map<String, TdfBoundDeletionDecision> boundDecisions = const {},
    Map<String, TdfRecoveryResolution> recoveryResolutions = const {},
    Set<String> freshlyRecoveredIds = const <String>{},
    Set<String> tombstonedLocationIds = const <String>{},
    Set<String> deletedLabelsLocal = const <String>{},
    Set<String> deletedLabelsIncoming = const <String>{},
    Set<String>? validLabelIds,
    Map<String, TdfLabel> postCascadeLabelsById = const <String, TdfLabel>{},
    TdfCleanupMode cleanupMode = TdfCleanupMode.finalStage,
    SyncBoardIndices? indices,
  }) {
    final maps = _resolveBoardMaps<TaskItem>(
      boards,
      cachedPrimary: indices?.primaryTasks,
      cachedSecondary: indices?.secondaryTasks,
      cachedBaseline: indices?.baselineTasks,
      hasIndices: indices != null,
      extract: (board) => board.allTasks,
      idOf: (task) => task.id,
    );
    final context = _reconcileContext(boards, options);
    final allTaskIds = <String>{...maps.primary.keys, ...maps.secondary.keys};
    final previewContext = _buildPreviewPrerequisiteContext(
      allTaskIds: allTaskIds,
      primaryMap: maps.primary,
      secondaryMap: maps.secondary,
      baselineMap: maps.baseline,
      initialDeleted: initialDeleted,
      context: context,
      resolutions: resolutions,
      boundDecisions: boundDecisions,
      recoveryResolutions: recoveryResolutions,
      freshlyRecoveredIds: freshlyRecoveredIds,
    );

    final accumulator = _newAccumulator<TaskItem, TdfDeletedTaskRecord>(
      initialDeleted,
    );
    final uncleanedById = <String, TaskItem>{};
    final undeletedIds = <String>{};
    var retired = false;

    for (final id in allTaskIds) {
      final primaryTask = maps.primary[id];
      final secondaryTask = maps.secondary[id];
      if (primaryTask != null && secondaryTask != null) {
        continue;
      }
      if (_reconcileOneSidedEntity<TaskItem, TdfDeletedTaskRecord>(
        adapter: _taskAdapter,
        id: id,
        entities: (primaryTask, secondaryTask, maps.baseline?[id]),
        context: context,
        accumulator: accumulator,
        resolutions: resolutions,
        boundDecisions: boundDecisions,
        recoveryResolutions: recoveryResolutions,
        freshlyRecoveredIds: freshlyRecoveredIds,
        isUnchangedFromBaseline: (surviving, baseTask) =>
            _isTaskUnchangedFromBaseline(
              surviving,
              baseTask,
              previewLiveTasksById: previewContext.liveById,
              previewDeletedTaskIds: previewContext.deletedIds,
              nowUtc: context.now,
            ),
        onLiveAdded: (addedId, task) => uncleanedById[addedId] = task,
        onUndeleted: (restoredId, restored) {
          uncleanedById[restoredId] = restored;
          undeletedIds.add(restoredId);
        },
      )) {
        retired = true;
      }
    }

    final mergedHeadersById = <String, TaskItem>{
      for (final task in accumulator.live) task.id: task,
      ...previewContext.twoSidedHeadersById,
    };
    final mergedDeletedTaskIds = <String>{
      ...accumulator.deleted.keys,
      ...accumulator.discarded,
    };
    final orderedLive = <TaskItem>[];
    final oneSidedById = _indexById(accumulator.live, (task) => task.id);
    final logDebug = AppLogger.shouldLog(LogLevel.debug);
    final debugEntries = logDebug
        ? <({String event, Map<String, Object?> fields})>[]
        : null;
    var unchangedTwoSidedCount = 0;
    var reconciledTwoSidedCount = 0;

    for (final id in allTaskIds) {
      final primaryTask = maps.primary[id];
      final secondaryTask = maps.secondary[id];
      if (primaryTask != null && secondaryTask != null) {
        final step = _reconcileTwoSidedTask(
          id: id,
          local: primaryTask,
          incoming: secondaryTask,
          baseline: maps.baseline?[id],
          now: context.now,
          cleanupMode: cleanupMode,
          mergedLiveTasksById: mergedHeadersById,
          mergedDeletedTaskIds: mergedDeletedTaskIds,
          tombstonedLocationIds: tombstonedLocationIds,
          deletedLabelsLocal: deletedLabelsLocal,
          deletedLabelsIncoming: deletedLabelsIncoming,
          validLabelIds: validLabelIds,
          postCascadeLabelsById: postCascadeLabelsById,
          uncleanedOut: uncleanedById,
          debugEntriesOut: debugEntries,
        );
        orderedLive.add(step.task);
        if (step.wasUnchanged) {
          unchangedTwoSidedCount++;
        } else {
          reconciledTwoSidedCount++;
        }
      } else if (oneSidedById[id] case final oneSided?) {
        orderedLive.add(oneSided);
      }
    }

    if (debugEntries != null &&
        (unchangedTwoSidedCount > 0 || reconciledTwoSidedCount > 0)) {
      debugEntries.add((
        event: 'sync.reconcile.summary',
        fields: <String, Object?>{
          'total': unchangedTwoSidedCount + reconciledTwoSidedCount,
          'unchanged': unchangedTwoSidedCount,
          'reconciled': reconciledTwoSidedCount,
        },
      ));
      AppLogger.eventBatch(LogLevel.debug, LogTag.sync, debugEntries);
    }

    return TaskReconciliationOutcome(
      liveTasks: orderedLive,
      deletedTasksById: accumulator.deleted,
      conflictedIds: accumulator.conflicted,
      ambiguousIds: accumulator.ambiguous,
      retiredByUndelete: retired,
      uncleanedLiveTasksById: uncleanedById,
      undeletedTaskIds: undeletedIds,
      discardedTaskIds: accumulator.discarded,
      explicitlyDeletedTaskIds: accumulator.explicitlyDeleted,
    );
  }

  /// Computes symmetric Phase 1 generation refresh flags `(primaryRefresh, secondaryRefresh)` (`TDF-REC-001`).
  static ({bool primaryRefresh, bool secondaryRefresh})
  resolveGenerationRefreshFlags(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    int? effectiveAckGen,
    bool requireAcknowledgedGeneration,
  ) {
    final (primary, secondary, _) = boards;
    final leftGen = primary.deletedBlock.generation;
    final rightGen = secondary.deletedBlock.generation;
    final primaryRefresh =
        (effectiveAckGen != null && rightGen > effectiveAckGen) ||
        rightGen > leftGen ||
        (effectiveAckGen == null &&
            (requireAcknowledgedGeneration || rightGen > 0));
    final secondaryRefresh = leftGen > rightGen;
    return (primaryRefresh: primaryRefresh, secondaryRefresh: secondaryRefresh);
  }

  /// Strips deleted or discarded labels from [tasks], applies `TDF-MERGE-011` `scoped` flood protection, and validates remaining label references.
  static List<TaskItem> stripDeletedLabelsAndValidateReferences(
    List<TaskItem> tasks,
    Set<String> validIds,
    Map<String, TdfDeletedLabelRecord> deletedById,
    List<TdfLabel>? baselineLabels, {
    Set<String> discardedLabelIds = const <String>{},
    Set<String> explicitlyDeletedLabelIds = const <String>{},
    Set<String> knownScopedLabelIds = const <String>{},
    Set<String>? evictedFromQueueOut,
    (TaskBoard, TaskBoard, TaskBoard?)? boards,
    Set<String>? mutatedByNowCascadeOut,
    DateTime? now,
    SyncBoardIndices? indices,
  }) {
    final baseIds = <String>{
      if (baselineLabels != null)
        for (final label in baselineLabels) label.id,
    };
    final scopedIds = <String>{
      ...knownScopedLabelIds,
      if (baselineLabels != null)
        for (final label in baselineLabels)
          if (label.isScoped && !validIds.contains(label.id)) label.id,
    };
    final maps = boards != null
        ? _resolveBoardMaps<TaskItem>(
            boards,
            cachedPrimary: indices?.primaryTasks,
            cachedSecondary: indices?.secondaryTasks,
            cachedBaseline: indices?.baselineTasks,
            hasIndices: indices != null,
            extract: (board) => board.allTasks,
            idOf: (task) => task.id,
          )
        : (
            primary: indices?.primaryTasks ?? const <String, TaskItem>{},
            secondary: indices?.secondaryTasks ?? const <String, TaskItem>{},
            baseline: indices?.baselineTasks,
          );
    final baselineMap = maps.baseline ?? const <String, TaskItem>{};
    final alreadyQueuedUnlabelled = boards != null
        ? _computeAlreadyQueuedUnlabelledTaskIds(
            boards.$1,
            boards.$2,
            maps.primary,
            maps.secondary,
          )
        : const <String>{};
    return <TaskItem>[
      for (final task in tasks)
        _stripDeletedLabelsFromSingleTask(
          task,
          validIds,
          deletedById,
          baseIds,
          discardedLabelIds: discardedLabelIds,
          explicitlyDeletedLabelIds: explicitlyDeletedLabelIds,
          scopedLabelSet: scopedIds,
          alreadyQueuedUnlabelledTaskIds: alreadyQueuedUnlabelled,
          evictedFromQueueOut: evictedFromQueueOut,
          sourceVariants: (
            maps.primary[task.id],
            maps.secondary[task.id],
            baselineMap[task.id],
          ),
          mutatedByNowCascadeOut: mutatedByNowCascadeOut,
          now: now,
        ),
    ];
  }

  /// Strips deleted or discarded locations from [labels], updates revisions (`TDF-MERGE-004` / `TDF-DEL-003`), and validates remaining location references.
  static List<TdfLabel> stripDeletedLocationsFromLabelsAndValidate(
    List<TdfLabel> labels,
    Set<String> validLocationIds,
    Map<String, TdfDeletedLocationRecord> deletedLocationsById,
    List<TdfLocation>? baselineLocations, {
    Set<String> discardedLocationIds = const <String>{},
    Set<String> explicitlyDeletedLocationIds = const <String>{},
    (TaskBoard, TaskBoard, TaskBoard?)? boards,
    DateTime? now,
    SyncBoardIndices? indices,
  }) {
    final baseIds = <String>{
      if (baselineLocations != null)
        for (final location in baselineLocations) location.id,
    };
    final maps = boards != null
        ? _resolveBoardMaps<TdfLabel>(
            boards,
            cachedPrimary: indices?.primaryLabels,
            cachedSecondary: indices?.secondaryLabels,
            cachedBaseline: indices?.baselineLabels,
            hasIndices: indices != null,
            extract: (board) => board.labels,
            idOf: (label) => label.id,
          )
        : (
            primary: indices?.primaryLabels ?? const <String, TdfLabel>{},
            secondary: indices?.secondaryLabels ?? const <String, TdfLabel>{},
            baseline: indices?.baselineLabels,
          );
    final baselineMap = maps.baseline ?? const <String, TdfLabel>{};
    return <TdfLabel>[
      for (final label in labels)
        _stripDeletedLocationsFromSingleLabel(
          label,
          validLocationIds,
          deletedLocationsById,
          baseIds,
          discardedLocationIds: discardedLocationIds,
          explicitlyDeletedLocationIds: explicitlyDeletedLocationIds,
          sourceVariants: (
            maps.primary[label.id],
            maps.secondary[label.id],
            baselineMap[label.id],
          ),
          now: now,
        ),
    ];
  }

  /// Strips deleted or discarded locations from [tasks] (inserting `condition location any` when a live assigned label still carries a location rule) and validates remaining location references.
  static List<TaskItem> stripDeletedLocationsFromTasksAndValidate(
    List<TaskItem> tasks,
    Set<String> validLocationIds,
    Map<String, TdfDeletedLocationRecord> deletedLocationsById,
    List<TdfLocation>? baselineLocations,
    Map<String, TdfLabel> postCascadeLabelsById, {
    Set<String> discardedLocationIds = const <String>{},
    Set<String> explicitlyDeletedLocationIds = const <String>{},
    Set<String>? mutatedByNowCascadeOut,
    DateTime? now,
  }) {
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
          discardedLocationIds: discardedLocationIds,
          explicitlyDeletedLocationIds: explicitlyDeletedLocationIds,
          mutatedByNowCascadeOut: mutatedByNowCascadeOut,
          now: now,
        ),
    ];
  }

  /// Verifies asymmetric `secondary.deleted.generation >= effectiveAckGen` (`TDF-REC-001`) and completion-counter monotonicity (`TDF-MERGE-010`).
  static void verifyGenerationsAndCompletionHistory(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    int? effectiveAckGen, {
    SyncBoardIndices? indices,
  }) {
    final (primary, secondary, baseline) = boards;
    final rightGen = secondary.deletedBlock.generation;
    if (effectiveAckGen != null && rightGen < effectiveAckGen) {
      throw const TdfSyncOutcomeException(
        kind: TdfSyncOutcomeKind.syncGenerationRollback,
        message: 'Shared deletion history generation is lower than the acknowledged generation.',
      );
    }
    if (baseline == null) {
      return;
    }
    final primaryMap =
        indices?.primaryTasks ??
        _indexById(primary.allTasks, (task) => task.id);
    final secondaryMap =
        indices?.secondaryTasks ??
        _indexById(secondary.allTasks, (task) => task.id);
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

  /// Builds preview live task headers and non-conflicting deleted/retired task IDs for `TDF-DEL-002` and `TDF-REC-001` baseline hygiene.
  static ({
    Map<String, TaskItem> liveById,
    Map<String, TaskItem> twoSidedHeadersById,
    Set<String> deletedIds,
  })
  _buildPreviewPrerequisiteContext({
    required Set<String> allTaskIds,
    required Map<String, TaskItem> primaryMap,
    required Map<String, TaskItem> secondaryMap,
    required Map<String, TaskItem>? baselineMap,
    required Map<String, TdfDeletedTaskRecord> initialDeleted,
    required _ReconcileContext context,
    required Map<String, TdfDeletionResolution> resolutions,
    required Map<String, TdfBoundDeletionDecision> boundDecisions,
    required Map<String, TdfRecoveryResolution> recoveryResolutions,
    required Set<String> freshlyRecoveredIds,
  }) {
    final liveById = <String, TaskItem>{};
    final twoSidedHeadersById = <String, TaskItem>{};
    final deletedIds = <String>{
      for (final id in initialDeleted.keys)
        if (!allTaskIds.contains(id)) id,
    };
    var pendingCandidates = <_PreviewDeleteCandidate>[];

    for (final id in allTaskIds) {
      _processSinglePreviewTask(
        id: id,
        primaryTask: primaryMap[id],
        secondaryTask: secondaryMap[id],
        baselineTask: baselineMap?[id],
        initialDeleted: initialDeleted,
        context: context,
        resolutions: resolutions,
        boundDecisions: boundDecisions,
        recoveryResolutions: recoveryResolutions,
        freshlyRecoveredIds: freshlyRecoveredIds,
        liveById: liveById,
        twoSidedHeadersById: twoSidedHeadersById,
        deletedIds: deletedIds,
        pendingCandidates: pendingCandidates,
      );
    }

    while (pendingCandidates.isNotEmpty) {
      final pass = _promoteUnchangedPreviewCandidates(
        pendingCandidates,
        liveById: liveById,
        deletedIds: deletedIds,
        nowUtc: context.now,
      );
      if (!pass.promotedAny) {
        break;
      }
      pendingCandidates = pass.remaining;
    }

    return (
      liveById: liveById,
      twoSidedHeadersById: twoSidedHeadersById,
      deletedIds: deletedIds,
    );
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

  /// Appends newly introduced `<location-id>` condition references across [entities] into [target].
  static void _collectNewlyReferencedConditionLocations<T extends Object>({
    required Iterable<T> entities,
    required Set<String> excludedIds,
    required Map<String, T> baselineById,
    required String Function(T entity) idOf,
    required List<TaskCondition> Function(T entity) conditionsOf,
    required Set<String> target,
  }) {
    for (final entity in entities) {
      final id = idOf(entity);
      if (excludedIds.contains(id)) {
        continue;
      }
      final currentLocs = TdfMetadata.collectDistinctLocationIds(
        conditionsOf(entity),
      );
      final baseEntity = baselineById[id];
      if (baseEntity != null) {
        final baseLocs = TdfMetadata.collectDistinctLocationIds(
          conditionsOf(baseEntity),
        );
        _collectAddedStrings(currentLocs, baseLocs, target);
      } else {
        target.addAll(currentLocs);
      }
    }
  }

  /// Returns task IDs already listed in `queue` with `labelIds.isEmpty` on either [primary] or [secondary] (`TDF-MERGE-011` Point 1).
  static Set<String> _computeAlreadyQueuedUnlabelledTaskIds(
    TaskBoard primary,
    TaskBoard secondary,
    Map<String, TaskItem> primaryMap,
    Map<String, TaskItem> secondaryMap,
  ) {
    final result = <String>{};
    for (final id in primary.queueBlock.taskIds) {
      final task = primaryMap[id];
      if (task != null && task.labelIds.isEmpty) {
        result.add(id);
      }
    }
    for (final id in secondary.queueBlock.taskIds) {
      final task = secondaryMap[id];
      if (task != null && task.labelIds.isEmpty) {
        result.add(id);
      }
    }
    return result;
  }

  /// Computes `decisionRevision = max(now, eachObservedRevision + 1 second)` (`TDF-DEL-003`).
  static DateTime _computeDecisionRevision(
    (DateTime, DateTime, DateTime?) revisions,
    DateTime now,
  ) {
    final (liveRev, deletedRev, baseRev) = revisions;
    var maxObserved = liveRev.isAfter(deletedRev) ? liveRev : deletedRev;
    if (baseRev != null && baseRev.isAfter(maxObserved)) {
      maxObserved = baseRev;
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

  /// Computes one-sided entity IDs resolved to explicit `Delete` or recovery `discard` (`TDF-DEL-002`).
  static Set<String>
  _computeExplicitlyDeletedIds<T extends Object, D extends Object>({
    required _EntityReconciliationAdapter<T, D> adapter,
    required _EntityBoardMaps<T> maps,
    required Map<String, D> initialDeleted,
    required _ReconcileContext context,
    required Map<String, TdfDeletionResolution> resolutions,
    required Map<String, TdfBoundDeletionDecision> boundDecisions,
    required Map<String, TdfRecoveryResolution> recoveryResolutions,
    required Set<String> freshlyRecoveredIds,
  }) {
    final allIds = <String>{...maps.primary.keys, ...maps.secondary.keys};
    final result = <String>{};
    for (final id in allIds) {
      if (_isEntityExplicitlyDeletedOrDiscarded<T, D>(
        adapter: adapter,
        id: id,
        primaryEntity: maps.primary[id],
        secondaryEntity: maps.secondary[id],
        baselineEntity: maps.baseline?[id],
        initialDeleted: initialDeleted,
        context: context,
        resolutions: resolutions,
        boundDecisions: boundDecisions,
        recoveryResolutions: recoveryResolutions,
        freshlyRecoveredIds: freshlyRecoveredIds,
      )) {
        result.add(id);
      }
    }
    return result;
  }

  /// Filters [locationIds] against [validLocationIds], [deletedLocationsById], [baselineLocationSet], and [discardedLocationIds].
  static ({List<String> retainedIds, bool strippedAny, bool strippedByMutation})
  _filterLocationIdsForEntity({
    required String entityKind,
    required String entityId,
    required List<String> locationIds,
    required Set<String> validLocationIds,
    required Map<String, TdfDeletedLocationRecord> deletedLocationsById,
    required Set<String> baselineLocationSet,
    required Set<String> discardedLocationIds,
    required Set<String> explicitlyDeletedLocationIds,
  }) {
    final retained = <String>[];
    var stripped = false;
    var byMutation = false;

    for (final locationId in locationIds) {
      if (validLocationIds.contains(locationId)) {
        retained.add(locationId);
        continue;
      }
      final deletedRecord = deletedLocationsById[locationId];
      if (deletedRecord != null ||
          baselineLocationSet.contains(locationId) ||
          discardedLocationIds.contains(locationId)) {
        stripped = true;
        if (explicitlyDeletedLocationIds.contains(locationId) ||
            discardedLocationIds.contains(locationId)) {
          byMutation = true;
        }
        continue;
      }
      throw TdfException(
        kind: TdfErrorKind.unknownLocationReference,
        line: 1,
        message:
            'Merged $entityKind "$entityId" references undeclared location "$locationId".',
      );
    }
    return (
      retainedIds: retained,
      strippedAny: stripped,
      strippedByMutation: byMutation,
    );
  }

  /// Finalizes a post-cascade entity [candidate] with its deterministic `TDF-MERGE-004` / `TDF-DEL-003` revision.
  static T _finalizePostCascadeEntity<T extends Object>({
    required T original,
    required T candidate,
    required bool strippedByMutation,
    required (T?, T?, T?) sourceVariants,
    required DateTime? now,
    required DateTime Function(T entity) effectiveModifiedAtOf,
    required DateTime? Function(T entity) modifiedAtOf,
    required int Function(T left, T right) compareVersions,
    required bool Function(T reference, T target) matchesPayload,
    required T Function(T entity, DateTime? modifiedAt) withModifiedAt,
    required bool checkOneSidedSourceMatch,
  }) {
    if (strippedByMutation && now != null) {
      return withModifiedAt(
        candidate,
        TaskItem.nextModifiedTimestamp(now, effectiveModifiedAtOf(original)),
      );
    }
    final (primaryEntity, secondaryEntity, baselineEntity) = sourceVariants;
    if (primaryEntity != null && secondaryEntity != null) {
      var greatest = compareVersions(primaryEntity, secondaryEntity) >= 0
          ? primaryEntity
          : secondaryEntity;
      if (baselineEntity != null &&
          compareVersions(baselineEntity, greatest) > 0) {
        greatest = baselineEntity;
      }
      if (matchesPayload(greatest, candidate)) {
        return withModifiedAt(candidate, modifiedAtOf(greatest));
      }
      var maxObserved = _laterDate(
        effectiveModifiedAtOf(primaryEntity),
        effectiveModifiedAtOf(secondaryEntity),
      );
      if (baselineEntity != null) {
        maxObserved = _laterDate(
          maxObserved,
          effectiveModifiedAtOf(baselineEntity),
        );
      }
      return withModifiedAt(candidate, _validatedPlusOneSecond(maxObserved));
    }
    if (checkOneSidedSourceMatch) {
      final sourceEntity = primaryEntity ?? secondaryEntity;
      if (sourceEntity != null && matchesPayload(sourceEntity, candidate)) {
        return withModifiedAt(candidate, modifiedAtOf(sourceEntity));
      }
      final baseMod = effectiveModifiedAtOf(sourceEntity ?? original);
      return withModifiedAt(candidate, _validatedPlusOneSecond(baseMod));
    }
    return withModifiedAt(
      candidate,
      _validatedPlusOneSecond(effectiveModifiedAtOf(original)),
    );
  }

  /// Returns whether any label in [labelIds] has a post-cascade `LocationTaskCondition` in [postCascadeLabelsById].
  static bool _hasLiveLabelLocationRule(
    List<String> labelIds,
    Map<String, TdfLabel> postCascadeLabelsById,
  ) {
    for (final labelId in labelIds) {
      final label = postCascadeLabelsById[labelId];
      if (label != null &&
          TdfMetadata.hasLocationConditionRule(label.conditions)) {
        return true;
      }
    }
    return false;
  }

  /// Indexes [items] by the key returned from [idOf].
  static Map<String, T> _indexById<T>(
    Iterable<T> items,
    String Function(T item) idOf,
  ) => <String, T>{for (final item in items) idOf(item): item};

  /// Returns whether one-sided entity [id] is resolved to explicit `Delete` or recovery `discard`.
  static bool
  _isEntityExplicitlyDeletedOrDiscarded<T extends Object, D extends Object>({
    required _EntityReconciliationAdapter<T, D> adapter,
    required String id,
    required T? primaryEntity,
    required T? secondaryEntity,
    required T? baselineEntity,
    required Map<String, D> initialDeleted,
    required _ReconcileContext context,
    required Map<String, TdfDeletionResolution> resolutions,
    required Map<String, TdfBoundDeletionDecision> boundDecisions,
    required Map<String, TdfRecoveryResolution> recoveryResolutions,
    required Set<String> freshlyRecoveredIds,
  }) {
    if (primaryEntity != null && secondaryEntity != null) {
      return false;
    }
    final surviving = primaryEntity ?? secondaryEntity;
    if (surviving == null || freshlyRecoveredIds.contains(id)) {
      return false;
    }
    final isStale = primaryEntity != null
        ? context.primaryRefresh
        : context.secondaryRefresh;
    var record = initialDeleted[id];
    if (record == null && baselineEntity != null && !isStale) {
      final synthAt = TaskItem.nextModifiedTimestamp(
        context.now,
        adapter.effectiveModifiedAtOf(baselineEntity),
      );
      record = adapter.makeBaselineTombstone(id, synthAt, baselineEntity);
    }
    if (record != null) {
      return _resolveEffectiveDecision<T, D>(
            adapter: adapter,
            surviving: surviving,
            deletedRecord: record,
            resolutions: resolutions,
            boundDecisions: boundDecisions,
          ) ==
          TdfDeletionResolution.delete;
    }
    return isStale && recoveryResolutions[id] == TdfRecoveryResolution.discard;
  }

  /// Returns whether [task] is unchanged relative to [baseTask] (ignoring `TDF-CLEAN-001` automatic block-cleanup-only changes).
  static bool _isTaskUnchangedFromBaseline(
    TaskItem task,
    TaskItem baseTask, {
    required Map<String, TaskItem> previewLiveTasksById,
    required Set<String> previewDeletedTaskIds,
    required DateTime nowUtc,
  }) {
    if (task.completions != baseTask.completions) {
      return false;
    }
    if (TdfPayloadComparison.taskPayloadsEqual(task, baseTask)) {
      return task.effectiveModifiedAt == baseTask.effectiveModifiedAt;
    }
    final bothOpen =
        !task.isCompleted &&
        task.completedAt == null &&
        !baseTask.isCompleted &&
        baseTask.completedAt == null;
    if (!bothOpen) {
      return false;
    }
    return TdfPayloadComparison.taskPayloadsEqualModuloBlockCleanup(
      left: task,
      right: baseTask,
      liveTasksById: previewLiveTasksById,
      deletedTaskIds: previewDeletedTaskIds,
      nowUtc: nowUtc,
    );
  }

  /// Returns the later of [left] and optional [right].
  static DateTime _laterDate(DateTime left, DateTime? right) =>
      (right != null && right.isAfter(left)) ? right : left;

  /// Verifies whether [bound] matches [surviving] and [deletedRecord] (`TDF-DEL-003`).
  static bool _matchesBoundDecision<T extends Object, D extends Object>({
    required _EntityReconciliationAdapter<T, D> adapter,
    required TdfBoundDeletionDecision bound,
    required T surviving,
    required D deletedRecord,
  }) {
    if (bound.expectedLiveModifiedAt case final expectedMod?
        when TaskItem.normalizeTimestamp(expectedMod) !=
            adapter.effectiveModifiedAtOf(surviving)) {
      return false;
    }
    if (bound.expectedDeletionAt case final expectedDel?
        when TaskItem.normalizeTimestamp(expectedDel) !=
            adapter.deletedAtOf(deletedRecord)) {
      return false;
    }
    if (bound.expectedLivePayloadSignature case final expectedSig?
        when expectedSig != adapter.payloadSignatureOf(surviving)) {
      return false;
    }
    return true;
  }

  /// Returns the maximum of three integers.
  static int _max3Int(int first, int second, int third) {
    final maxFirstSecond = first >= second ? first : second;
    return maxFirstSecond >= third ? maxFirstSecond : third;
  }

  /// Creates an empty mutable [_EntityAccumulator] seeded with [initialDeleted].
  static _EntityAccumulator<T, D> _newAccumulator<
    T extends Object,
    D extends Object
  >(Map<String, D> initialDeleted) => (
    live: <T>[],
    deleted: <String, D>{...initialDeleted},
    conflicted: <String>[],
    ambiguous: <String>[],
    discarded: <String>{},
    explicitlyDeleted: <String>{},
  );

  /// Classifies a single task [id] into [liveById], [twoSidedHeadersById], [deletedIds], or [pendingCandidates] for prerequisite previewing.
  static void _processSinglePreviewTask({
    required String id,
    required TaskItem? primaryTask,
    required TaskItem? secondaryTask,
    required TaskItem? baselineTask,
    required Map<String, TdfDeletedTaskRecord> initialDeleted,
    required _ReconcileContext context,
    required Map<String, TdfDeletionResolution> resolutions,
    required Map<String, TdfBoundDeletionDecision> boundDecisions,
    required Map<String, TdfRecoveryResolution> recoveryResolutions,
    required Set<String> freshlyRecoveredIds,
    required Map<String, TaskItem> liveById,
    required Map<String, TaskItem> twoSidedHeadersById,
    required Set<String> deletedIds,
    required List<_PreviewDeleteCandidate> pendingCandidates,
  }) {
    if (primaryTask != null && secondaryTask != null) {
      final header = TdfEntityMerger.previewMergedTaskPrerequisiteHeader(
        local: primaryTask,
        incoming: secondaryTask,
        baseline: baselineTask,
      );
      twoSidedHeadersById[id] = header;
      liveById[id] = header;
      return;
    }
    final surviving = primaryTask ?? secondaryTask;
    if (surviving == null) {
      return;
    }
    if (freshlyRecoveredIds.contains(id)) {
      liveById[id] = surviving;
      return;
    }
    final isStale = primaryTask != null
        ? context.primaryRefresh
        : context.secondaryRefresh;
    var previewRecord = initialDeleted[id];
    if (previewRecord == null && baselineTask != null && !isStale) {
      final synthAt = TaskItem.nextModifiedTimestamp(
        context.now,
        baselineTask.effectiveModifiedAt,
      );
      previewRecord = TdfDeletedTaskRecord(
        taskId: id,
        deletedAt: synthAt,
        completionsCheckpoint: baselineTask.completions,
      );
    }
    if (previewRecord != null) {
      final decision =
          _resolveEffectiveDecision<TaskItem, TdfDeletedTaskRecord>(
            adapter: _taskAdapter,
            surviving: surviving,
            deletedRecord: previewRecord,
            resolutions: resolutions,
            boundDecisions: boundDecisions,
          );
      if (decision == TdfDeletionResolution.undelete) {
        final maxComp = _max3Int(
          surviving.completions,
          baselineTask?.completions ?? 0,
          previewRecord.completionsCheckpoint,
        );
        liveById[id] = surviving.copyWith(completions: maxComp);
        return;
      }
      if (decision == TdfDeletionResolution.delete) {
        deletedIds.add(id);
        return;
      }
      liveById[id] = surviving;
      if (baselineTask != null) {
        pendingCandidates.add((
          id: id,
          surviving: surviving,
          baselineTask: baselineTask,
        ));
      }
      return;
    }
    if (baselineTask != null) {
      if (recoveryResolutions[id] == TdfRecoveryResolution.discard) {
        deletedIds.add(id);
        return;
      }
      liveById[id] = surviving;
      pendingCandidates.add((
        id: id,
        surviving: surviving,
        baselineTask: baselineTask,
      ));
      return;
    }
    if (!isStale) {
      liveById[id] = surviving;
    } else if (recoveryResolutions[id] == TdfRecoveryResolution.discard) {
      deletedIds.add(id);
    } else {
      liveById[id] = surviving;
    }
  }

  /// Promotes unchanged one-sided deletion candidates into [deletedIds] and removes them from [liveById] (`TDF-DEL-002`).
  static ({List<_PreviewDeleteCandidate> remaining, bool promotedAny})
  _promoteUnchangedPreviewCandidates(
    List<_PreviewDeleteCandidate> candidates, {
    required Map<String, TaskItem> liveById,
    required Set<String> deletedIds,
    required DateTime nowUtc,
  }) {
    final remaining = <_PreviewDeleteCandidate>[];
    var promotedAny = false;
    for (final candidate in candidates) {
      if (_isTaskUnchangedFromBaseline(
        candidate.surviving,
        candidate.baselineTask,
        previewLiveTasksById: liveById,
        previewDeletedTaskIds: deletedIds,
        nowUtc: nowUtc,
      )) {
        liveById.remove(candidate.id);
        deletedIds.add(candidate.id);
        promotedAny = true;
      } else {
        remaining.add(candidate);
      }
    }
    return (remaining: remaining, promotedAny: promotedAny);
  }

  /// Precomputes symmetric generation refresh flags and [now] for entity reconciliation.
  static _ReconcileContext _reconcileContext(
    (TaskBoard, TaskBoard, TaskBoard?) boards,
    (int?, bool, DateTime) options,
  ) {
    final (ackGen, requireAck, now) = options;
    final flags = resolveGenerationRefreshFlags(boards, ackGen, requireAck);
    return (
      primaryRefresh: flags.primaryRefresh,
      secondaryRefresh: flags.secondaryRefresh,
      now: now,
    );
  }

  /// Reconciles a one-sided entity [id] and returns whether an explicit `Undelete` retired a deletion record.
  static bool _reconcileOneSidedEntity<T extends Object, D extends Object>({
    required _EntityReconciliationAdapter<T, D> adapter,
    required String id,
    required (T?, T?, T?) entities,
    required _ReconcileContext context,
    required _EntityAccumulator<T, D> accumulator,
    required Map<String, TdfDeletionResolution> resolutions,
    required Map<String, TdfBoundDeletionDecision> boundDecisions,
    required Map<String, TdfRecoveryResolution> recoveryResolutions,
    required Set<String> freshlyRecoveredIds,
    required bool Function(T surviving, T baseline) isUnchangedFromBaseline,
    void Function(String id, T entity)? onLiveAdded,
    void Function(String id, T restored)? onUndeleted,
  }) {
    final (primaryEntity, secondaryEntity, baselineEntity) = entities;
    final surviving = primaryEntity ?? secondaryEntity;
    if (surviving == null) {
      return false;
    }
    if (freshlyRecoveredIds.contains(id)) {
      accumulator.live.add(surviving);
      onLiveAdded?.call(id, surviving);
      return false;
    }
    final isStale = primaryEntity != null
        ? context.primaryRefresh
        : context.secondaryRefresh;
    final unchanged =
        baselineEntity != null &&
        isUnchangedFromBaseline(surviving, baselineEntity);

    final D conflictRecord;
    if (accumulator.deleted[id] case final existing?) {
      if (unchanged) {
        adapter.onUnchangedExistingTombstone?.call(
          id,
          existing,
          surviving,
          baselineEntity,
          accumulator.deleted,
        );
        return false;
      }
      conflictRecord = existing;
    } else if (baselineEntity != null) {
      if (isStale) {
        if (unchanged ||
            recoveryResolutions[id] == TdfRecoveryResolution.discard) {
          accumulator.discarded.add(id);
        } else {
          accumulator.ambiguous.add(id);
        }
        return false;
      }
      final synthAt = TaskItem.nextModifiedTimestamp(
        context.now,
        adapter.effectiveModifiedAtOf(baselineEntity),
      );
      conflictRecord = adapter.makeBaselineTombstone(
        id,
        synthAt,
        baselineEntity,
      );
      if (unchanged) {
        accumulator.deleted[id] = conflictRecord;
        return false;
      }
    } else {
      if (isStale) {
        if (recoveryResolutions[id] == TdfRecoveryResolution.discard) {
          accumulator.discarded.add(id);
        } else {
          accumulator.ambiguous.add(id);
        }
      } else {
        accumulator.live.add(surviving);
        onLiveAdded?.call(id, surviving);
      }
      return false;
    }
    return _resolveDeletionConflict<T, D>(
      adapter: adapter,
      surviving: surviving,
      baselineEntity: baselineEntity,
      deletedRecord: conflictRecord,
      context: context,
      accumulator: accumulator,
      resolutions: resolutions,
      boundDecisions: boundDecisions,
      onUndeleted: onUndeleted,
    );
  }

  /// Reconciles all two-sided and one-sided entities of type [T] (`TdfLabel` or `TdfLocation`).
  static ({_EntityAccumulator<T, D> accumulator, bool retiredByUndelete})
  _reconcileSimpleEntities<T extends Object, D extends Object>({
    required _EntityReconciliationAdapter<T, D> adapter,
    required _EntityBoardMaps<T> maps,
    required Map<String, D> initialDeleted,
    required _ReconcileContext context,
    required Map<String, TdfDeletionResolution> resolutions,
    required Map<String, TdfBoundDeletionDecision> boundDecisions,
    required Map<String, TdfRecoveryResolution> recoveryResolutions,
    required Set<String> freshlyRecoveredIds,
    required String logEventName,
    required T Function(T local, T incoming, T? baseline) mergeTwoSided,
    required bool Function(String id, T surviving, T baseline)
    isUnchangedFromBaseline,
  }) {
    final accumulator = _newAccumulator<T, D>(initialDeleted);
    var retired = false;
    final logDebug = AppLogger.shouldLog(LogLevel.debug);
    for (final id in <String>{...maps.primary.keys, ...maps.secondary.keys}) {
      final primaryEntity = maps.primary[id];
      final secondaryEntity = maps.secondary[id];
      final baselineEntity = maps.baseline?[id];
      if (primaryEntity != null && secondaryEntity != null) {
        final merged = mergeTwoSided(
          primaryEntity,
          secondaryEntity,
          baselineEntity,
        );
        if (logDebug) {
          final winner = identical(merged, primaryEntity)
              ? 'primary'
              : (identical(merged, secondaryEntity) ? 'secondary' : 'merged');
          AppLogger.event(
            LogLevel.debug,
            LogTag.sync,
            logEventName,
            fields: <String, Object?>{
              'id': id,
              'winner': winner,
              'primary_rev': adapter
                  .effectiveModifiedAtOf(primaryEntity)
                  .toIso8601String(),
              'secondary_rev': adapter
                  .effectiveModifiedAtOf(secondaryEntity)
                  .toIso8601String(),
            },
          );
        }
        accumulator.live.add(merged);
        continue;
      }
      if (_reconcileOneSidedEntity<T, D>(
        adapter: adapter,
        id: id,
        entities: (primaryEntity, secondaryEntity, baselineEntity),
        context: context,
        accumulator: accumulator,
        resolutions: resolutions,
        boundDecisions: boundDecisions,
        recoveryResolutions: recoveryResolutions,
        freshlyRecoveredIds: freshlyRecoveredIds,
        isUnchangedFromBaseline: (surviving, baseEntity) =>
            isUnchangedFromBaseline(id, surviving, baseEntity),
      )) {
        retired = true;
      }
    }
    return (accumulator: accumulator, retiredByUndelete: retired);
  }

  /// Reconciles a two-sided task [id] present on both boards and records its `uncleaned` counterpart into [uncleanedOut].
  static ({TaskItem task, bool wasUnchanged}) _reconcileTwoSidedTask({
    required String id,
    required TaskItem local,
    required TaskItem incoming,
    required TaskItem? baseline,
    required DateTime now,
    required TdfCleanupMode cleanupMode,
    required Map<String, TaskItem> mergedLiveTasksById,
    required Set<String> mergedDeletedTaskIds,
    required Set<String> tombstonedLocationIds,
    required Set<String> deletedLabelsLocal,
    required Set<String> deletedLabelsIncoming,
    required Set<String>? validLabelIds,
    required Map<String, TdfLabel> postCascadeLabelsById,
    required Map<String, TaskItem> uncleanedOut,
    List<({String event, Map<String, Object?> fields})>? debugEntriesOut,
  }) {
    final mergedResult = TdfEntityMerger.mergeTaskWithBaselineAndUncleaned(
      local: local,
      incoming: incoming,
      baseline: baseline,
      evaluationTime: now,
      cleanupMode: cleanupMode,
      mergedLiveTasksById: mergedLiveTasksById,
      mergedDeletedTaskIds: mergedDeletedTaskIds,
      tombstonedLocationIds: tombstonedLocationIds,
      deletedLabelsLocal: deletedLabelsLocal,
      deletedLabelsIncoming: deletedLabelsIncoming,
      validLabelIds: validLabelIds,
      postCascadeLabelsById: postCascadeLabelsById,
    );
    uncleanedOut[id] = mergedResult.uncleaned;
    final mergedTask = mergedResult.merged;
    final isIdenticalUnchanged =
        mergedResult.wasUnchangedIdentity ||
        (local == incoming && mergedTask == local);
    if (debugEntriesOut != null && !isIdenticalUnchanged) {
      final winner =
          TdfPayloadComparison.taskPayloadsEqual(mergedTask, local) &&
              mergedTask.modifiedAt == local.modifiedAt
          ? 'primary'
          : (TdfPayloadComparison.taskPayloadsEqual(mergedTask, incoming) &&
                    mergedTask.modifiedAt == incoming.modifiedAt
                ? 'secondary'
                : 'merged');
      debugEntriesOut.add((
        event: 'sync.reconcile.task',
        fields: <String, Object?>{
          'id': id,
          'winner': winner,
          'primary_rev': local.effectiveModifiedAt.toIso8601String(),
          'secondary_rev': incoming.effectiveModifiedAt.toIso8601String(),
        },
      ));
    }
    return (task: mergedTask, wasUnchanged: isIdenticalUnchanged);
  }

  /// Resolves primary, secondary, and optional baseline maps for entity type [T], reusing cached [SyncBoardIndices] when provided.
  static _EntityBoardMaps<T> _resolveBoardMaps<T extends Object>(
    (TaskBoard, TaskBoard, TaskBoard?) boards, {
    required Map<String, T>? cachedPrimary,
    required Map<String, T>? cachedSecondary,
    required Map<String, T>? cachedBaseline,
    required bool hasIndices,
    required Iterable<T> Function(TaskBoard board) extract,
    required String Function(T entity) idOf,
  }) {
    final (primary, secondary, baseline) = boards;
    return (
      primary: cachedPrimary ?? _indexById(extract(primary), idOf),
      secondary: cachedSecondary ?? _indexById(extract(secondary), idOf),
      baseline: hasIndices
          ? cachedBaseline
          : (baseline != null ? _indexById(extract(baseline), idOf) : null),
    );
  }

  /// Applies the verified conflict resolution (or records a `DeletionConflict`) for [surviving] and [deletedRecord] (`TDF-DEL-003`).
  static bool _resolveDeletionConflict<T extends Object, D extends Object>({
    required _EntityReconciliationAdapter<T, D> adapter,
    required T surviving,
    required T? baselineEntity,
    required D deletedRecord,
    required _ReconcileContext context,
    required _EntityAccumulator<T, D> accumulator,
    required Map<String, TdfDeletionResolution> resolutions,
    required Map<String, TdfBoundDeletionDecision> boundDecisions,
    void Function(String id, T restored)? onUndeleted,
  }) {
    final id = adapter.idOf(surviving);
    final resolution = _resolveEffectiveDecision<T, D>(
      adapter: adapter,
      surviving: surviving,
      deletedRecord: deletedRecord,
      resolutions: resolutions,
      boundDecisions: boundDecisions,
    );
    if (resolution == null) {
      accumulator.conflicted.add(id);
      return false;
    }
    final revisions = (
      adapter.effectiveModifiedAtOf(surviving),
      adapter.deletedAtOf(deletedRecord),
      baselineEntity != null
          ? adapter.effectiveModifiedAtOf(baselineEntity)
          : null,
    );
    final revision = _computeDecisionRevision(revisions, context.now);
    switch (resolution) {
      case TdfDeletionResolution.delete:
        accumulator.deleted[id] = adapter.makeResolvedDeleteRecord(
          id,
          revision,
          surviving,
          baselineEntity,
          deletedRecord,
        );
        accumulator.explicitlyDeleted.add(id);
        return false;
      case TdfDeletionResolution.undelete:
        accumulator.deleted.remove(id);
        final restored = adapter.buildUndeletedEntity(
          surviving,
          baselineEntity,
          deletedRecord,
          revision,
        );
        accumulator.live.add(restored);
        onUndeleted?.call(id, restored);
        return true;
    }
  }

  /// Resolves the verified [TdfDeletionResolution] for [surviving] and [deletedRecord] from [boundDecisions] or [resolutions].
  static TdfDeletionResolution?
  _resolveEffectiveDecision<T extends Object, D extends Object>({
    required _EntityReconciliationAdapter<T, D> adapter,
    required T surviving,
    required D deletedRecord,
    required Map<String, TdfDeletionResolution> resolutions,
    required Map<String, TdfBoundDeletionDecision> boundDecisions,
  }) {
    final id = adapter.idOf(surviving);
    if (boundDecisions[id] case final bound?) {
      if (!_matchesBoundDecision<T, D>(
        adapter: adapter,
        bound: bound,
        surviving: surviving,
        deletedRecord: deletedRecord,
      )) {
        return null;
      }
      return bound.resolution;
    }
    return resolutions[id];
  }

  /// Strips deleted or discarded labels from a single [task], applies `TDF-MERGE-011` `scoped` flood protection, and validates remaining label references.
  static TaskItem _stripDeletedLabelsFromSingleTask(
    TaskItem task,
    Set<String> validLabelIds,
    Map<String, TdfDeletedLabelRecord> deletedLabelsById,
    Set<String> baselineLabelSet, {
    required Set<String> discardedLabelIds,
    required Set<String> explicitlyDeletedLabelIds,
    required Set<String> scopedLabelSet,
    required Set<String> alreadyQueuedUnlabelledTaskIds,
    required Set<String>? evictedFromQueueOut,
    required (TaskItem?, TaskItem?, TaskItem?) sourceVariants,
    required Set<String>? mutatedByNowCascadeOut,
    required DateTime? now,
  }) {
    if (task.labelIds.isEmpty) {
      return task;
    }
    final retained = <String>[];
    var strippedAny = false;
    var strippedByMutation = false;
    var allBeforeWereScoped = true;

    for (final labelId in task.labelIds) {
      if (!scopedLabelSet.contains(labelId)) {
        allBeforeWereScoped = false;
      }
      if (validLabelIds.contains(labelId)) {
        retained.add(labelId);
        continue;
      }
      final isKnownDeleted =
          deletedLabelsById.containsKey(labelId) ||
          baselineLabelSet.contains(labelId) ||
          discardedLabelIds.contains(labelId);
      if (!isKnownDeleted) {
        throw TdfException(
          kind: TdfErrorKind.unknownLabelReference,
          line: 1,
          message:
              'Merged task "${task.id}" references undeclared label "$labelId".',
        );
      }
      strippedAny = true;
      strippedByMutation =
          strippedByMutation ||
          explicitlyDeletedLabelIds.contains(labelId) ||
          discardedLabelIds.contains(labelId);
    }

    if (!strippedAny) {
      return task;
    }
    if (strippedByMutation) {
      mutatedByNowCascadeOut?.add(task.id);
    }
    final isOpen = !task.isCompleted && task.completedAt == null;
    final lostLastScopedLabel =
        isOpen &&
        retained.isEmpty &&
        allBeforeWereScoped &&
        !alreadyQueuedUnlabelledTaskIds.contains(task.id);
    if (lostLastScopedLabel && evictedFromQueueOut != null) {
      evictedFromQueueOut.add(task.id);
    }
    final candidate = task.copyWith(
      labelIds: retained,
      isPriority: !lostLastScopedLabel && task.isPriority,
    );
    return _finalizePostCascadeEntity<TaskItem>(
      original: task,
      candidate: candidate,
      strippedByMutation: strippedByMutation,
      sourceVariants: sourceVariants,
      now: now,
      effectiveModifiedAtOf: (item) => item.effectiveModifiedAt,
      modifiedAtOf: (item) => item.modifiedAt,
      compareVersions: TdfPayloadComparison.compareTaskVersions,
      matchesPayload: (reference, target) =>
          reference.completions == target.completions &&
          TdfPayloadComparison.compareTaskPayloads(reference, target) == 0,
      withModifiedAt: (item, modifiedAt) => item.copyWith(
        modifiedAt: modifiedAt,
        clearModifiedAt: modifiedAt == null,
      ),
      checkOneSidedSourceMatch: false,
    );
  }

  /// Strips deleted or discarded locations from [conditions] of a label or task, inserting `condition location any` when [insertResetWhenEmptied] is true.
  static ({
    List<TaskCondition> conditions,
    bool strippedAny,
    bool strippedByMutation,
  })
  _stripDeletedLocationsFromConditions({
    required String entityKind,
    required String entityId,
    required List<TaskCondition> conditions,
    required Set<String> validLocationIds,
    required Map<String, TdfDeletedLocationRecord> deletedLocationsById,
    required Set<String> baselineLocationSet,
    required Set<String> discardedLocationIds,
    required Set<String> explicitlyDeletedLocationIds,
    required bool insertResetWhenEmptied,
  }) {
    final updatedConditions = <TaskCondition>[];
    var strippedAny = false;
    var strippedByMutation = false;

    for (final rule in conditions) {
      if (rule is! LocationTaskCondition || rule.locationIds.isEmpty) {
        updatedConditions.add(rule);
        continue;
      }
      final filtered = _filterLocationIdsForEntity(
        entityKind: entityKind,
        entityId: entityId,
        locationIds: rule.locationIds,
        validLocationIds: validLocationIds,
        deletedLocationsById: deletedLocationsById,
        baselineLocationSet: baselineLocationSet,
        discardedLocationIds: discardedLocationIds,
        explicitlyDeletedLocationIds: explicitlyDeletedLocationIds,
      );
      strippedAny = strippedAny || filtered.strippedAny;
      strippedByMutation = strippedByMutation || filtered.strippedByMutation;
      if (filtered.retainedIds.isNotEmpty) {
        updatedConditions.add(
          LocationTaskCondition(locationIds: filtered.retainedIds),
        );
      } else if (insertResetWhenEmptied) {
        updatedConditions.add(
          const GroupResetTaskCondition(targetGroup: ConditionGroup.location),
        );
      }
    }
    return (
      conditions: updatedConditions,
      strippedAny: strippedAny,
      strippedByMutation: strippedByMutation,
    );
  }

  /// Strips deleted or discarded locations from a single [label] and validates remaining location references.
  static TdfLabel _stripDeletedLocationsFromSingleLabel(
    TdfLabel label,
    Set<String> validLocationIds,
    Map<String, TdfDeletedLocationRecord> deletedLocationsById,
    Set<String> baselineLocationSet, {
    required Set<String> discardedLocationIds,
    required Set<String> explicitlyDeletedLocationIds,
    required (TdfLabel?, TdfLabel?, TdfLabel?) sourceVariants,
    required DateTime? now,
  }) {
    if (label.conditions.isEmpty) {
      return label;
    }
    final stripped = _stripDeletedLocationsFromConditions(
      entityKind: 'label',
      entityId: label.id,
      conditions: label.conditions,
      validLocationIds: validLocationIds,
      deletedLocationsById: deletedLocationsById,
      baselineLocationSet: baselineLocationSet,
      discardedLocationIds: discardedLocationIds,
      explicitlyDeletedLocationIds: explicitlyDeletedLocationIds,
      insertResetWhenEmptied: false,
    );
    if (!stripped.strippedAny) {
      return label;
    }
    return _finalizePostCascadeEntity<TdfLabel>(
      original: label,
      candidate: label.copyWith(conditions: stripped.conditions),
      strippedByMutation: stripped.strippedByMutation,
      sourceVariants: sourceVariants,
      now: now,
      effectiveModifiedAtOf: (item) => item.effectiveModifiedAt,
      modifiedAtOf: (item) => item.modifiedAt,
      compareVersions: TdfPayloadComparison.compareLabelVersions,
      matchesPayload: (reference, target) =>
          TdfPayloadComparison.compareLabelPayloads(reference, target) == 0,
      withModifiedAt: (item, modifiedAt) => item.copyWith(
        modifiedAt: modifiedAt,
        clearModifiedAt: modifiedAt == null,
      ),
      checkOneSidedSourceMatch: true,
    );
  }

  /// Strips deleted or discarded locations from a single [task] and validates remaining location references.
  static TaskItem _stripDeletedLocationsFromSingleTask(
    TaskItem task,
    Set<String> validLocationIds,
    Map<String, TdfDeletedLocationRecord> deletedLocationsById,
    Set<String> baselineLocationSet,
    Map<String, TdfLabel> postCascadeLabelsById, {
    required Set<String> discardedLocationIds,
    required Set<String> explicitlyDeletedLocationIds,
    required Set<String>? mutatedByNowCascadeOut,
    required DateTime? now,
  }) {
    if (task.conditions.isEmpty) {
      return task;
    }
    final stripped = _stripDeletedLocationsFromConditions(
      entityKind: 'task',
      entityId: task.id,
      conditions: task.conditions,
      validLocationIds: validLocationIds,
      deletedLocationsById: deletedLocationsById,
      baselineLocationSet: baselineLocationSet,
      discardedLocationIds: discardedLocationIds,
      explicitlyDeletedLocationIds: explicitlyDeletedLocationIds,
      insertResetWhenEmptied: _hasLiveLabelLocationRule(
        task.labelIds,
        postCascadeLabelsById,
      ),
    );
    if (!stripped.strippedAny) {
      return task;
    }
    if (stripped.strippedByMutation) {
      mutatedByNowCascadeOut?.add(task.id);
    }
    if (stripped.strippedByMutation && now != null) {
      return task.copyWith(
        conditions: stripped.conditions,
        modifiedAt: TaskItem.nextModifiedTimestamp(
          now,
          task.effectiveModifiedAt,
        ),
      );
    }
    return task.copyWith(
      conditions: stripped.conditions,
      modifiedAt: _validatedPlusOneSecond(task.effectiveModifiedAt),
    );
  }

  /// Adds one second to [timestamp] and validates TDF calendar bounds.
  static DateTime _validatedPlusOneSecond(DateTime timestamp) {
    final bumped = timestamp.add(const Duration(seconds: 1));
    if (!TdfCalendar.isWithinTimestampBounds(bumped)) {
      throw const TdfException(
        kind: TdfErrorKind.invalidTimestamp,
        line: 1,
        message: 'Merged revision exceeds maximum supported timestamp.',
      );
    }
    return bumped;
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
    this.uncleanedLiveTasksById = const <String, TaskItem>{},
    this.undeletedTaskIds = const <String>{},
    this.discardedTaskIds = const <String>{},
    this.explicitlyDeletedTaskIds = const <String>{},
  });

  /// Task IDs requiring user recovery after deletion history expiry or completion regression.
  final List<String> ambiguousIds;

  /// Task IDs with unresolved deletion vs. modification conflicts.
  final List<String> conflictedIds;

  /// Active task deletion records keyed by task ID.
  final Map<String, TdfDeletedTaskRecord> deletedTasksById;

  /// Stale-side task IDs discarded during generation refresh or explicit `discard` recovery (`TDF-REC-002`).
  final Set<String> discardedTaskIds;

  /// Task IDs resolved via explicit `Delete` during `DeletionConflict` resolution (`TDF-DEL-003`).
  final Set<String> explicitlyDeletedTaskIds;

  /// Surviving reconciled live tasks.
  final List<TaskItem> liveTasks;

  /// Whether at least one deletion record was retired by an explicit undelete resolution.
  final bool retiredByUndelete;

  /// Pre-cleanup merged task payloads keyed by task ID for `TDF-MERGE-004` revision selection.
  final Map<String, TaskItem> uncleanedLiveTasksById;

  /// Task IDs resolved via explicit `Undelete` during this reconciliation pass.
  final Set<String> undeletedTaskIds;
}

/// Typed adapter parameterizing shared entity/tombstone reconciliation across labels, locations, and tasks.
@immutable
class _EntityReconciliationAdapter<T extends Object, D extends Object> {
  /// Creates an [_EntityReconciliationAdapter] binding entity [T] and tombstone [D] operations.
  const _EntityReconciliationAdapter({
    required this.idOf,
    required this.effectiveModifiedAtOf,
    required this.deletedAtOf,
    required this.payloadSignatureOf,
    required this.makeBaselineTombstone,
    required this.makeResolvedDeleteRecord,
    required this.buildUndeletedEntity,
    this.onUnchangedExistingTombstone,
  });

  /// Builds the restored entity [T] when an explicit `Undelete` resolves a conflict at [revision].
  final T Function(T surviving, T? baseline, D deletedRecord, DateTime revision)
  buildUndeletedEntity;

  /// Extracts the deletion timestamp from tombstone [record].
  final DateTime Function(D record) deletedAtOf;

  /// Extracts the effective modification timestamp from [entity].
  final DateTime Function(T entity) effectiveModifiedAtOf;

  /// Extracts the canonical entity identifier from [entity].
  final String Function(T entity) idOf;

  /// Constructs a baseline-implied tombstone record [D] for [id] at [deletedAt].
  final D Function(String id, DateTime deletedAt, T baselineEntity)
  makeBaselineTombstone;

  /// Constructs a resolved explicit-delete tombstone record [D] at [revision].
  final D Function(
    String id,
    DateTime revision,
    T surviving,
    T? baseline,
    D existingRecord,
  )
  makeResolvedDeleteRecord;

  /// Optional hook invoked when an unchanged one-sided entity already has a tombstone in [deleted].
  final void Function(
    String id,
    D existing,
    T surviving,
    T baseline,
    Map<String, D> deleted,
  )?
  onUnchangedExistingTombstone;

  /// Computes the normalized payload signature of [entity] for bound conflict decision verification.
  final String Function(T entity) payloadSignatureOf;
}

/// Mutable accumulator used while reconciling entities of type [T] and deletion records of type [D].
typedef _EntityAccumulator<T extends Object, D extends Object> = ({
  List<T> live,
  Map<String, D> deleted,
  List<String> conflicted,
  List<String> ambiguous,
  Set<String> discarded,
  Set<String> explicitlyDeleted,
});

/// Indexed primary, secondary, and optional baseline maps for a single entity type [T].
typedef _EntityBoardMaps<T extends Object> = ({
  Map<String, T> primary,
  Map<String, T> secondary,
  Map<String, T>? baseline,
});

/// One-sided deletion candidate pending baseline-cleanup unchanged verification during prerequisite preview.
typedef _PreviewDeleteCandidate = ({
  String id,
  TaskItem surviving,
  TaskItem baselineTask,
});

/// Precomputed symmetric generation refresh flags and evaluation instant.
typedef _ReconcileContext = ({
  bool primaryRefresh,
  bool secondaryRefresh,
  DateTime now,
});
