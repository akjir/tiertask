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

import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/app_workspace.dart';
import '../models/task_board.dart';
import '../models/task_board_undo.dart';
import '../models/task_item.dart';
import '../models/task_tier.dart';
import '../models/tdf_metadata.dart';
import '../models/tdf_sync_metadata.dart';
import '../models/tdf_timezone.dart';
import '../models/webdav_config.dart';
import '../models/workspace_sync_state.dart';
import '../repositories/local_file_repository.dart';
import '../repositories/webdav_repository.dart';
import '../services/app_logger.dart';
import '../services/tdf_importer.dart';
import 'config_providers.dart';
import 'location_providers.dart';
import 'sync_providers.dart';
import 'workspace_providers.dart';

/// Provides the transient OS file-lock retry delay (`250 ms` by default) for external local watch reads.
final localFileWatchReadRetryDelayProvider = Provider<Duration>(
  (ref) => TaskNotifier.defaultWatchReadRetryDelay,
);

/// Provides the [TaskNotifier] managing the in-memory [TaskBoard] and persistence.
final taskNotifierProvider = AsyncNotifierProvider<TaskNotifier, TaskBoard>(
  TaskNotifier.new,
  retry: disableProviderRetry,
);

/// Provides the ephemeral [TaskUndoState] for the active workspace session.
final taskUndoStateProvider =
    NotifierProvider<TaskUndoStateNotifier, TaskUndoState>(
      TaskUndoStateNotifier.new,
    );

/// Manages the in-memory [TaskBoard] and synchronizes mutations to local files and WebDAV.
class TaskNotifier extends AsyncNotifier<TaskBoard> {
  /// Default single-retry delay (`250 ms`) when an external local `.tdf` read encounters a transient OS file lock.
  static const Duration defaultWatchReadRetryDelay = Duration(
    milliseconds: 250,
  );

  String? _conflictWatchDigest;
  Future<void>? _inFlightSync;
  String? _lastFailedWatchDigest;
  int _mutationEpoch = 0;
  int _nextUndoSequence = 0;
  final Map<String, DateTime> _pendingDeletedLabelTimestamps =
      <String, DateTime>{};
  final Map<String, DateTime> _pendingDeletedLocationTimestamps =
      <String, DateTime>{};
  final Set<int> _rolledBackEpochs = <int>{};
  final ListQueue<TaskUndoEntry> _undoStack = ListQueue<TaskUndoEntry>();
  String? _undoWorkspaceId;

  /// Returns the current [TaskBoard] snapshot or an empty board if not yet loaded.
  TaskBoard get _currentBoard => state.asData?.value ?? TaskBoard.empty();

  @override
  Future<TaskBoard> build() async {
    ref
        .read(workspaceUnloadCoordinatorProvider)
        .register(prepareForWorkspaceUnload);
    _syncUndoWorkspaceId(ref.read(activeWorkspaceProvider).asData?.value.id);
    _pendingDeletedLabelTimestamps.clear();
    _pendingDeletedLocationTimestamps.clear();
    _conflictWatchDigest = null;
    _lastFailedWatchDigest = null;
    state = const AsyncLoading();
    final selectedConfig = await ref.watch(
      webDavConfigProvider.selectAsync(
        (value) => value.copyWith(localWatchEnabled: true),
      ),
    );
    final activeWorkspaceId = ref.watch(
      activeWorkspaceProvider.select((value) => value.asData?.value.id),
    );
    final config =
        ref.read(webDavConfigProvider).asData?.value ?? selectedConfig;
    _syncUndoWorkspaceId(activeWorkspaceId);
    if (!config.hasActiveStorage) {
      return TaskBoard.empty();
    }
    try {
      return await _runSyncWithStatus(config, isInitialLoad: true);
    } on TdfSyncOutcomeException {
      await _recordConflictWatchDigestIfLocal(config);
      rethrow;
    }
  }

  /// Adds a new TDF `label` block with [name] and optional `#RRGGBB` [color] and persists to storage.
  Future<void> addLabel(
    String name, {
    String? color,
    String? id,
    String? note,
    bool isScoped = false,
    List<TaskCondition> conditions = const [],
    DateTime? currentDate,
  }) async {
    final (utcNow, _) = _resolveTimestamps(currentDate);
    await _commitMutation(
      _currentBoard.addLabel(
        name,
        color: color,
        id: id,
        note: note,
        isScoped: isScoped,
        conditions: conditions,
        currentDate: utcNow,
      ),
    );
  }

  /// Adds a new TDF `location` block with [name], [latitude], [longitude], and [radiusMeters] and persists to storage.
  Future<void> addLocation(
    String name, {
    required double latitude,
    required double longitude,
    required double radiusMeters,
    String source = 'manual',
    String? id,
    String? note,
    DateTime? currentDate,
  }) async {
    final (utcNow, _) = _resolveTimestamps(currentDate);
    await _commitMutation(
      _currentBoard.addLocation(
        name,
        latitude: latitude,
        longitude: longitude,
        radius: radiusMeters,
        source: source,
        id: id,
        note: note,
        currentDate: utcNow,
      ),
    );
  }

  /// Adds a new task to [targetTier] (defaulting to [TaskTier.planned]), runs the
  /// Auto-Pull Cascade, and persists to the active `.tdf` storage backend.
  Future<void> addTask(
    String title, {
    String? note,
    TaskTier targetTier = TaskTier.planned,
    bool isPriority = false,
    bool subtasksAutoFinish = false,
    List<SubtaskItem> subtasks = const [],
    List<String> labelIds = const [],
    DateTime? dueAt,
    TaskOrigin? origin,
    DateTime? suspendedAt,
    bool isSuspendedForever = false,
    TaskRepeatRule? repeatRule,
    List<String> blockedByTaskIds = const [],
    List<TdfTaskDependency>? dependencies,
    List<TaskLink> links = const [],
    List<TaskCondition> conditions = const [],
    DateTime? currentDate,
    String? id,
  }) async {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    await _commitMutation(
      _currentBoard.addTask(
        title,
        note: note,
        targetTier: targetTier,
        isPriority: isPriority,
        subtasksAutoFinish: subtasksAutoFinish,
        subtasks: subtasks,
        labelIds: labelIds,
        dueAt: dueAt,
        origin: origin,
        suspendedAt: suspendedAt,
        isSuspendedForever: isSuspendedForever,
        repeatRule: repeatRule,
        blockedByTaskIds: blockedByTaskIds,
        dependencies: dependencies,
        links: links,
        conditions: conditions,
        currentDate: utcNow,
        localEvaluationTime: localNow,
        id: id,
      ),
    );
  }

  /// Moves an active task immediately to Tier 4 ([TaskTier.blocked]) and persists to storage.
  Future<void> blockTask(
    String taskId, {
    DateTime? suspendedUntil,
    DateTime? currentDate,
  }) async {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    await _commitMutation(
      _currentBoard.blockTask(
        taskId,
        suspendedUntil: suspendedUntil,
        currentDate: utcNow,
        localEvaluationTime: localNow,
      ),
    );
  }

  /// Marks an active task as done in Tier 6 ([TaskTier.completed]), prunes expired tasks,
  /// triggers the Auto-Pull Cascade, and persists to storage.
  Future<void> completeTask(
    String taskId, {
    int? expectedCompletions,
    DateTime? currentDate,
  }) async {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    final boardBefore = _currentBoard;
    final taskBefore = boardBefore.findTask(taskId);
    final updatedBoard = boardBefore.completeTask(
      taskId,
      expectedCompletions: expectedCompletions,
      currentDate: utcNow,
      localEvaluationTime: localNow,
    );
    final updatedTask = updatedBoard.findTask(taskId);
    final undoEntry =
        taskBefore != null &&
            updatedTask != null &&
            updatedTask.completions > taskBefore.completions
        ? TaskBoardUndo.capture(
            sequence: ++_nextUndoSequence,
            kind: TaskUndoActionKind.complete,
            boardBefore: boardBefore,
            taskBefore: taskBefore,
          )
        : null;
    await _commitMutation(updatedBoard, undoEntry: undoEntry);
  }

  /// Deletes the label with [labelId], strips its reference from all tasks, and persists to storage.
  Future<void> deleteLabel(String labelId, {DateTime? currentDate}) async {
    final (utcNow, _) = _resolveTimestamps(currentDate);
    final existingLabel = _currentBoard.findLabel(labelId);
    final deleteTimestamp = TaskItem.nextModifiedTimestamp(
      utcNow,
      existingLabel?.effectiveModifiedAt ?? TdfLabel.defaultModifiedAt,
    );
    _pendingDeletedLabelTimestamps[labelId] = deleteTimestamp;
    await TaskSyncPipeline.persistPendingLabelDeletion(
      ref,
      labelId,
      deleteTimestamp,
    );
    await _commitMutation(
      _currentBoard.deleteLabel(labelId, currentDate: utcNow),
    );
  }

  /// Deletes the location with [locationId], strips its reference from all tasks and labels, and persists to storage.
  Future<void> deleteLocation(
    String locationId, {
    DateTime? currentDate,
  }) async {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    final existingLocation = _currentBoard.findLocation(locationId);
    final deleteTimestamp = TaskItem.nextModifiedTimestamp(
      utcNow,
      existingLocation?.effectiveModifiedAt ?? TdfLabel.defaultModifiedAt,
    );
    _pendingDeletedLocationTimestamps[locationId] = deleteTimestamp;
    await TaskSyncPipeline.persistPendingLocationDeletion(
      ref,
      locationId,
      deleteTimestamp,
    );
    await _commitMutation(
      _currentBoard.deleteLocation(
        locationId,
        currentDate: utcNow,
        localEvaluationTime: localNow,
      ),
    );
  }

  /// Deletes the task with [taskId], removes its `queue` entry, and persists to storage.
  Future<void> deleteTask(String taskId, {DateTime? currentDate}) async {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    final boardBefore = _currentBoard;
    final taskBefore = boardBefore.findTask(taskId);
    final updatedBoard = boardBefore.deleteTask(
      taskId,
      currentDate: utcNow,
      localEvaluationTime: localNow,
    );
    final undoEntry =
        taskBefore != null && updatedBoard.findTask(taskId) == null
        ? TaskBoardUndo.capture(
            sequence: ++_nextUndoSequence,
            kind: TaskUndoActionKind.delete,
            boardBefore: boardBefore,
            taskBefore: taskBefore,
          )
        : null;
    await _commitMutation(updatedBoard, undoEntry: undoEntry);
  }

  /// Downgrades an active task per `TDF_SPEC.md` Section 6.3 and persists to storage.
  Future<void> downgradeTask(
    String taskId, {
    String? activeFilterLabelId,
    DateTime? currentDate,
  }) async {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    final locationFix = ref.read(locationStateProvider).fix;
    final boardBefore = _currentBoard;
    final taskBefore = boardBefore.findTask(taskId);
    final updatedBoard = boardBefore.downgradeTask(
      taskId,
      activeLabelId: activeFilterLabelId,
      currentLatitude: locationFix?.latitude,
      currentLongitude: locationFix?.longitude,
      currentDate: utcNow,
      localEvaluationTime: localNow,
    );
    final updatedTask = updatedBoard.findTask(taskId);
    final didDowngradeMutate =
        taskBefore != null &&
        updatedTask != null &&
        (updatedTask != taskBefore ||
            !listEquals(
              updatedBoard.queueBlock.taskIds,
              boardBefore.queueBlock.taskIds,
            ));
    final undoEntry = didDowngradeMutate
        ? TaskBoardUndo.capture(
            sequence: ++_nextUndoSequence,
            kind: TaskUndoActionKind.downgrade,
            boardBefore: boardBefore,
            taskBefore: taskBefore,
          )
        : null;
    await _commitMutation(updatedBoard, undoEntry: undoEntry);
  }

  /// Explicitly imports and migrates a historical TDF (`0.2.0`–`0.5.1`) or `0.6.0` [rawTdf]
  /// document into `tdf 0.6.0`, invalidates any earlier synchronization baseline per
  /// `TDF_SPEC.md` Section 10.1, and persists the migrated document to active storage.
  Future<TdfImportResult> importLegacyTdf(
    String rawTdf, {
    TdfTimeZoneContext? sourceTimeZone,
    DateTime? currentDate,
  }) async {
    final importResult = await TaskSyncPipeline.importLegacyTdf(
      ref,
      rawTdf,
      sourceTimeZone: sourceTimeZone,
      currentDate: currentDate,
    );
    _conflictWatchDigest = null;
    _lastFailedWatchDigest = null;
    _clearUndoStack('import_tdf');
    state = AsyncData(importResult.board);
    return importResult;
  }

  /// Moves [taskId] within the shared `queue` block and persists to storage.
  Future<void> moveTaskInQueue(
    String taskId, {
    String? beforeTaskId,
    String? afterTaskId,
    DateTime? currentDate,
  }) async {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    await _commitMutation(
      _currentBoard.moveTaskInQueue(
        taskId,
        beforeTaskId: beforeTaskId,
        afterTaskId: afterTaskId,
        currentDate: utcNow,
        localEvaluationTime: localNow,
      ),
    );
  }

  /// Awaits any in-flight synchronization and flushes the outgoing [TaskBoard] to local storage if populated before switching workspaces.
  Future<void> prepareForWorkspaceUnload() async {
    await _flushOutgoingWorkspaceBoard();
    _clearUndoStack('workspace_unload');
  }

  /// Synchronizes and persists the in-memory [board] state across the configured local and WebDAV stages.
  Future<void> pushToRemote(
    TaskBoard board, {
    TaskBoard? fallbackBoard,
    Map<String, TdfDeletionResolution> taskConflictResolutions = const {},
    int? mutationEpoch,
  }) async {
    await _awaitInFlightSync();
    if (!ref.mounted) {
      return;
    }
    final operation = _executePushToRemote(
      board,
      fallbackBoard: fallbackBoard,
      taskConflictResolutions: taskConflictResolutions,
      mutationEpoch: mutationEpoch,
    );
    _inFlightSync = operation;
    try {
      await operation;
    } finally {
      if (identical(_inFlightSync, operation)) {
        _inFlightSync = null;
      }
    }
  }

  /// Reconciles external on-disk `.tdf` edits into memory (and WebDAV in `Both` mode) when the local digest changed.
  Future<bool> reconcileExternalLocalChanges() async {
    if (!_canStartExternalLocalReconcile()) {
      return false;
    }
    await _awaitInFlightSync();
    if (!ref.mounted) {
      return false;
    }
    final workspace = ref.read(activeWorkspaceProvider).asData?.value;
    final config =
        ref.read(webDavConfigProvider).asData?.value ?? workspace?.config;
    if (workspace == null ||
        config == null ||
        !_isExternalWatchActiveForConfig(config) ||
        (!state.hasValue && state.isLoading)) {
      return false;
    }
    final operation = _executeExternalLocalReconcile(workspace.id, config);
    _inFlightSync = operation;
    try {
      return await operation;
    } finally {
      if (identical(_inFlightSync, operation)) {
        _inFlightSync = null;
      }
    }
  }

  /// Restores a completed task to [targetTier] (defaulting to [TaskTier.planned]) per
  /// `TDF_SPEC.md` Section 6.5 and persists to storage.
  Future<void> restoreTask(
    String taskId, {
    TaskTier targetTier = TaskTier.planned,
    DateTime? currentDate,
  }) async {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    await _commitMutation(
      _currentBoard.restoreTask(
        taskId,
        targetTier: targetTier,
        currentDate: utcNow,
        localEvaluationTime: localNow,
      ),
    );
  }

  /// Schedules a task from `Someday` into the active pull cycle per `TDF_SPEC.md` Section 6.2 and persists to storage.
  Future<void> scheduleTask(
    String taskId, {
    bool isPriority = false,
    DateTime? currentDate,
  }) async {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    await _commitMutation(
      _currentBoard.scheduleTask(
        taskId,
        isPriority: isPriority,
        currentDate: utcNow,
        localEvaluationTime: localNow,
      ),
    );
  }

  /// Switches the active workspace's local `.tdf` file to [newConfig] without moving or deleting the previous file, initializes the target file if missing, and reloads the board.
  Future<void> selectLocalFile(WebDavConfig newConfig) async {
    await _flushOutgoingWorkspaceBoard();
    final previousConfig = resolveCurrentConfig(ref);
    final localizations = lookupAppLocalizations(
      newConfig.language.resolveLocale(PlatformDispatcher.instance.locale),
    );
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final targetRepo = LocalFileRepository(
      config: newConfig,
      baseDirectoryPath: ref.read(localStorageDirectoryPathProvider),
      inMemoryStore: ref.read(inMemoryLocalStoreProvider),
    );
    final targetPath = targetRepo.resolveFilePath();

    try {
      await settingsRepo.saveConfig(newConfig);
    } on WorkspaceException catch (error) {
      final message = switch (error.kind) {
        WorkspaceErrorKind.duplicateFilePath =>
          localizations.errorDuplicateWorkspaceFilePath,
        WorkspaceErrorKind.invalidFilePath =>
          localizations.errorInvalidLocalFilePath,
        _ => error.message,
      };
      throw LocalFileException(message, cause: error);
    }

    try {
      await targetRepo.initializeIfMissing();
    } on Object {
      await settingsRepo.saveConfig(previousConfig);
      rethrow;
    }

    final workspace = await ref.read(activeWorkspaceProvider.future);
    _pendingDeletedLabelTimestamps.clear();
    _pendingDeletedLocationTimestamps.clear();
    _conflictWatchDigest = null;
    _lastFailedWatchDigest = null;
    _clearUndoStack('select_local_file');
    await TaskSyncPipeline.resetLocalSyncBaseline(ref, workspace.id);
    await ref.read(webDavConfigProvider.notifier).updateConfig(newConfig);
    final updatedConfig = await ref.read(webDavConfigProvider.future);
    try {
      state = AsyncData(
        await _runSyncWithStatus(updatedConfig, isInitialLoad: true),
      );
    } on TdfSyncOutcomeException {
      await _recordConflictWatchDigestIfLocal(updatedConfig);
      rethrow;
    }
    AppLogger.info(
      LogTag.sync,
      'Selected local TDF file workspace=${workspace.id} path=$targetPath',
    );
  }

  /// Synchronizes the in-memory board with the configured local and/or WebDAV storage backends.
  Future<void> syncFromRemote() async {
    await _awaitInFlightSync();
    final operation = _executeSyncFromRemote();
    _inFlightSync = operation;
    try {
      await operation;
    } finally {
      if (identical(_inFlightSync, operation)) {
        _inFlightSync = null;
      }
    }
  }

  /// Tests storage access using [config], runs the two-stage merge pipeline, and updates the board.
  Future<void> testConnectionAndSync(WebDavConfig config) async {
    await _awaitInFlightSync();
    final operation = _executeTestConnectionAndSync(config);
    _inFlightSync = operation;
    try {
      await operation;
    } finally {
      if (identical(_inFlightSync, operation)) {
        _inFlightSync = null;
      }
    }
  }

  /// Toggles the subtask step at [stepIndex] on [taskId] and persists to storage.
  Future<void> toggleSubtask(
    String taskId,
    int stepIndex, {
    DateTime? currentDate,
  }) async {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    final boardBefore = _currentBoard;
    final taskBefore = boardBefore.findTask(taskId);
    final updatedBoard = boardBefore.toggleSubtask(
      taskId,
      stepIndex,
      currentDate: utcNow,
      localEvaluationTime: localNow,
    );
    final updatedTask = updatedBoard.findTask(taskId);
    final didAutoFinishComplete =
        taskBefore != null &&
        !taskBefore.isCompleted &&
        taskBefore.completedAt == null &&
        updatedTask != null &&
        updatedTask.completions > taskBefore.completions;
    final undoEntry = didAutoFinishComplete
        ? TaskBoardUndo.capture(
            sequence: ++_nextUndoSequence,
            kind: TaskUndoActionKind.complete,
            boardBefore: boardBefore,
            taskBefore: taskBefore,
          )
        : null;
    await _commitMutation(updatedBoard, undoEntry: undoEntry);
  }

  /// Pops and reverses the most recent undoable task mutation when available.
  Future<bool> undoLastAction({
    int? expectedSequence,
    DateTime? currentDate,
  }) async {
    if (_undoStack.isEmpty) {
      return false;
    }
    if (expectedSequence != null &&
        _undoStack.last.sequence != expectedSequence) {
      return false;
    }
    final entry = _undoStack.removeLast();
    ref
        .read(taskUndoStateProvider.notifier)
        .update(TaskUndoState(stackDepth: _undoStack.length));
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    final outcome = TaskBoardUndo.apply(
      _currentBoard,
      entry,
      utcNow: utcNow,
      localEvaluationTime: localNow,
    );
    if (outcome == null) {
      return false;
    }
    if (AppLogger.shouldLog(LogLevel.info)) {
      AppLogger.event(
        LogLevel.info,
        LogTag.domain,
        'task.undo.apply',
        fields: <String, Object?>{
          'id': entry.snapshotTask.id,
          'kind': entry.kind.name,
          'seq': entry.sequence,
          'remaining': _undoStack.length,
        },
      );
    }
    final persisted = await _commitMutation(
      outcome.board,
      taskConflictResolutions: outcome.taskConflictResolutions,
    );
    if (!persisted) {
      if (_undoStack.length < TaskBoardUndo.maxUndoEntries) {
        _undoStack.addLast(entry);
      }
      ref
          .read(taskUndoStateProvider.notifier)
          .update(TaskUndoState(stackDepth: _undoStack.length));
      if (AppLogger.shouldLog(LogLevel.warn)) {
        AppLogger.event(
          LogLevel.warn,
          LogTag.domain,
          'task.undo.rollback',
          fields: <String, Object?>{
            'id': entry.snapshotTask.id,
            'kind': entry.kind.name,
            'seq': entry.sequence,
            'direction': 'undo',
          },
        );
      }
      return false;
    }
    return true;
  }

  /// Updates an existing label with [labelId] and persists the updated board to storage.
  Future<void> updateLabel(
    String labelId, {
    String? name,
    String? color,
    bool clearColor = false,
    String? note,
    bool clearNote = false,
    bool? isScoped,
    List<TaskCondition>? conditions,
    DateTime? currentDate,
  }) async {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    await _commitMutation(
      _currentBoard.updateLabel(
        labelId,
        name: name,
        color: color,
        clearColor: clearColor,
        note: note,
        clearNote: clearNote,
        isScoped: isScoped,
        conditions: conditions,
        currentDate: utcNow,
        localEvaluationTime: localNow,
      ),
    );
  }

  /// Updates an existing location with [locationId] and persists the updated board to storage.
  Future<void> updateLocation(
    String locationId, {
    String? name,
    double? latitude,
    double? longitude,
    double? radiusMeters,
    String? source,
    bool clearSource = false,
    String? note,
    bool clearNote = false,
    DateTime? currentDate,
  }) async {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    await _commitMutation(
      _currentBoard.updateLocation(
        locationId,
        name: name,
        latitude: latitude,
        longitude: longitude,
        radius: radiusMeters,
        source: source,
        clearSource: clearSource,
        note: note,
        clearNote: clearNote,
        currentDate: utcNow,
        localEvaluationTime: localNow,
      ),
    );
  }

  /// Updates an existing task with [taskId] and persists the updated board to storage.
  Future<void> updateTask(
    String taskId, {
    required String title,
    String? note,
    TaskTier? targetTier,
    bool? isPriority,
    bool? subtasksAutoFinish,
    List<SubtaskItem>? subtasks,
    List<String>? labelIds,
    DateTime? dueAt,
    bool clearDueAt = false,
    TaskOrigin? origin,
    bool clearOrigin = false,
    DateTime? suspendedAt,
    bool? isSuspendedForever,
    bool clearSuspendedAt = false,
    TaskRepeatRule? repeatRule,
    bool clearRepeatRule = false,
    List<String>? blockedByTaskIds,
    List<TdfTaskDependency>? dependencies,
    List<TaskLink>? links,
    List<TaskCondition>? conditions,
    DateTime? currentDate,
  }) async {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    await _commitMutation(
      _currentBoard.updateTask(
        taskId,
        title: title,
        note: note,
        targetTier: targetTier,
        isPriority: isPriority,
        subtasksAutoFinish: subtasksAutoFinish,
        subtasks: subtasks,
        labelIds: labelIds,
        dueAt: dueAt,
        clearDueAt: clearDueAt,
        origin: origin,
        clearOrigin: clearOrigin,
        suspendedAt: suspendedAt,
        isSuspendedForever: isSuspendedForever,
        clearSuspendedAt: clearSuspendedAt,
        repeatRule: repeatRule,
        clearRepeatRule: clearRepeatRule,
        blockedByTaskIds: blockedByTaskIds,
        dependencies: dependencies,
        links: links,
        conditions: conditions,
        currentDate: utcNow,
        localEvaluationTime: localNow,
      ),
    );
  }

  /// Wipes and re-initializes the local `.tdf` file for [config], optionally creating a `.bak` backup first, and resets synchronization baselines.
  Future<void> wipeLocalFile(
    WebDavConfig config, {
    bool createBackup = false,
  }) => _executeWipe(
    config,
    isRemote: false,
    createBackup: createBackup,
    wipeTarget: () => ref
        .read(localFileRepositoryProvider)
        .wipeTdf(createBackup: createBackup),
  );

  /// Wipes and re-initializes the remote WebDAV `.tdf` file for [config], optionally creating a `.bak` backup first, and resets synchronization baselines.
  Future<void> wipeRemoteFile(
    WebDavConfig config, {
    bool createBackup = false,
  }) async {
    await _awaitInFlightSync();
    final localizations = lookupAppLocalizations(ref.read(appLocaleProvider));
    if (!config.storageMode.usesWebDav || !config.isWebDavConfigured) {
      final exception = WebDavException(localizations.errorWebDavNotConfigured);
      ref.read(syncStateProvider.notifier).setError(exception.toString());
      throw exception;
    }
    await _executeWipe(
      config,
      isRemote: true,
      createBackup: createBackup,
      wipeTarget: () => ref
          .read(webDavRepositoryProvider)
          .wipeTdf(createBackup: createBackup),
    );
  }

  /// Applies [nextBoard] to [state] and selectively prunes [_undoStack] when [workspaceId] and [epoch] remain current.
  void _applyExternalReconciledBoard({
    required String workspaceId,
    required int epoch,
    required TaskBoard? previousBoard,
    required TaskBoard nextBoard,
  }) {
    final isActive =
        ref.read(activeWorkspaceProvider).asData?.value.id == workspaceId;
    if (!isActive || epoch != _mutationEpoch) {
      return;
    }
    if (previousBoard == null) {
      _clearUndoStack('external_local_recovery');
    } else if (nextBoard != previousBoard) {
      _pruneInvalidatedUndoEntries(previousBoard, nextBoard);
    }
    state = AsyncData(nextBoard);
  }

  /// Awaits all currently running synchronization operations in FIFO order without propagating their exceptions.
  Future<void> _awaitInFlightSync() async {
    while (_inFlightSync != null) {
      final pending = _inFlightSync;
      if (pending == null) {
        break;
      }
      try {
        await pending;
      } on Object {
        // Proceed after in-flight sync finishes.
      }
    }
  }

  /// Returns `true` when synchronous workspace, configuration, and board-loading guards permit an external local reconcile.
  bool _canStartExternalLocalReconcile() {
    final workspace = ref.read(activeWorkspaceProvider).asData?.value;
    final config =
        ref.read(webDavConfigProvider).asData?.value ?? workspace?.config;
    if (workspace == null ||
        config == null ||
        !_isExternalWatchActiveForConfig(config)) {
      return false;
    }
    return state.hasValue || !state.isLoading;
  }

  /// Clears [_undoStack] for [reason] and optionally resets [taskUndoStateProvider].
  void _clearUndoStack(String reason, {bool resetProvider = true}) {
    final cleared = _undoStack.length;
    _rolledBackEpochs.clear();
    if (cleared > 0) {
      _undoStack.clear();
      if (AppLogger.shouldLog(LogLevel.info)) {
        AppLogger.event(
          LogLevel.info,
          LogTag.domain,
          'task.undo.clear',
          fields: <String, Object?>{'reason': reason, 'cleared': cleared},
        );
      }
    }
    if (resetProvider) {
      ref.read(taskUndoStateProvider.notifier).update(TaskUndoState.empty);
    }
  }

  /// Updates the in-memory board state and executes the two-stage persistence pipeline, rolling back on local failure.
  Future<bool> _commitMutation(
    TaskBoard updatedBoard, {
    TaskUndoEntry? undoEntry,
    Map<String, TdfDeletionResolution> taskConflictResolutions = const {},
  }) async {
    final epoch = ++_mutationEpoch;
    final previousBoard = _currentBoard;
    state = AsyncData(updatedBoard);
    final evictedEntry = undoEntry != null
        ? _recordOptimisticUndoEntry(undoEntry)
        : null;
    await pushToRemote(
      updatedBoard,
      fallbackBoard: previousBoard,
      taskConflictResolutions: taskConflictResolutions,
      mutationEpoch: epoch,
    );
    final rolledBack = _rolledBackEpochs.remove(epoch);
    if (rolledBack && undoEntry != null) {
      _rollbackOptimisticUndoEntry(undoEntry, evictedEntry: evictedEntry);
    }
    return !rolledBack;
  }

  /// Returns `true` when any dependent task in [dependentIds] changed between [previousBoard] and [nextBoard].
  bool _didAnyDependentChange(
    Set<String> dependentIds,
    TaskBoard previousBoard,
    TaskBoard nextBoard,
  ) {
    for (final dependentId in dependentIds) {
      if (previousBoard.findTask(dependentId) !=
          nextBoard.findTask(dependentId)) {
        return true;
      }
    }
    return false;
  }

  /// Executes digest-gated reconciliation of an external local `.tdf` file change for [workspaceId].
  Future<bool> _executeExternalLocalReconcile(
    String workspaceId,
    WebDavConfig config,
  ) async {
    final ({String content, String? digest, bool exists}) disk;
    try {
      disk = await _readWatchSnapshotWithRetry(workspaceId);
    } on LocalFileException catch (error) {
      if (!ref.mounted) {
        return false;
      }
      _logWatchError(workspaceId, config.storageMode, error);
      ref.read(syncStateProvider.notifier).setError(error.toString());
      return false;
    }
    if (!ref.mounted) {
      return false;
    }
    if (!disk.exists || disk.content.trim().isEmpty) {
      _logWatchSkip(workspaceId, 'missing_or_empty');
      return false;
    }
    final syncState = await ref
        .read(settingsRepositoryProvider)
        .loadWorkspaceSyncState(workspaceId);
    if (!ref.mounted) {
      return false;
    }
    final activeId = ref.read(activeWorkspaceProvider).asData?.value.id;
    if (activeId != workspaceId || !readCurrentConfig(ref).localWatchEnabled) {
      return false;
    }
    if (disk.digest != null && disk.digest == syncState.localSourceDigest) {
      _lastFailedWatchDigest = null;
      _conflictWatchDigest = null;
      _logWatchSkip(workspaceId, 'digest_unchanged');
      return false;
    }
    if (ref.read(syncStateProvider).hasOpenConflict &&
        (_conflictWatchDigest == null || disk.digest == _conflictWatchDigest)) {
      _conflictWatchDigest = disk.digest;
      _logWatchSkip(workspaceId, 'open_conflict');
      return false;
    }
    if (disk.digest != null && disk.digest == _lastFailedWatchDigest) {
      _logWatchSkip(workspaceId, 'repeat_failed_digest');
      return false;
    }
    return _runExternalWatchSynchronize(workspaceId, config, disk.digest);
  }

  /// Executes a single [pushToRemote] persistence pass for [board].
  Future<void> _executePushToRemote(
    TaskBoard board, {
    TaskBoard? fallbackBoard,
    Map<String, TdfDeletionResolution> taskConflictResolutions = const {},
    int? mutationEpoch,
  }) async {
    final workspace = await ref.read(activeWorkspaceProvider.future);
    final WebDavConfig config =
        ref.read(webDavConfigProvider).asData?.value ??
        await ref.read(webDavConfigProvider.future);
    if (!config.hasActiveStorage) {
      return;
    }

    var localStageSucceeded = false;
    ref.read(syncStateProvider.notifier).setSyncing();
    try {
      final converged = await TaskSyncPipeline.synchronize(
        ref,
        config,
        pendingDeletedLabelTimestamps: _pendingDeletedLabelTimestamps,
        pendingDeletedLocationTimestamps: _pendingDeletedLocationTimestamps,
        taskConflictResolutions: taskConflictResolutions,
        candidateBoard: board,
        candidateOriginBoard: fallbackBoard,
        onLocalStageMerged: (mergedBoard) {
          localStageSucceeded = true;
          _conflictWatchDigest = null;
          _lastFailedWatchDigest = null;
          if (mutationEpoch == null || mutationEpoch == _mutationEpoch) {
            state = AsyncData(mergedBoard);
          }
        },
      );
      final isCurrentEpoch =
          mutationEpoch == null || mutationEpoch == _mutationEpoch;
      if (isCurrentEpoch &&
          ref.read(activeWorkspaceProvider).asData?.value.id == workspace.id) {
        state = AsyncData(converged);
      }
      _conflictWatchDigest = null;
      _lastFailedWatchDigest = null;
      ref.read(syncStateProvider.notifier).setSuccess(DateTime.now());
    } on Object catch (error) {
      if (!localStageSucceeded) {
        if (mutationEpoch != null) {
          _rolledBackEpochs.add(mutationEpoch);
        }
        final isCurrentEpoch =
            mutationEpoch == null || mutationEpoch == _mutationEpoch;
        if (isCurrentEpoch &&
            fallbackBoard != null &&
            ref.read(activeWorkspaceProvider).asData?.value.id ==
                workspace.id) {
          state = AsyncData(fallbackBoard);
        }
      }
      if (error is TdfSyncOutcomeException) {
        ref.read(syncStateProvider.notifier).setConflict(error.toString());
        await _recordConflictWatchDigestIfLocal(config);
      } else {
        ref.read(syncStateProvider.notifier).setError(error.toString());
      }
    }
  }

  /// Executes a serialized [syncFromRemote] pass.
  Future<void> _executeSyncFromRemote() async {
    final config = await ref.read(webDavConfigProvider.future);
    final localizations = lookupAppLocalizations(ref.read(appLocaleProvider));
    if (config.storageMode.usesWebDav && !config.isWebDavConfigured) {
      ref
          .read(syncStateProvider.notifier)
          .setError(localizations.errorWebDavNotConfigured);
      return;
    }
    if (config.storageMode.usesLocal && !config.isLocalConfigured) {
      ref
          .read(syncStateProvider.notifier)
          .setError(localizations.errorInvalidLocalFilePath);
      return;
    }

    final existingBoard = state.asData?.value;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      try {
        final board = await _runSyncWithStatus(
          config,
          candidateBoard: existingBoard,
        );
        _conflictWatchDigest = null;
        _lastFailedWatchDigest = null;
        return board;
      } on TdfSyncOutcomeException {
        await _recordConflictWatchDigestIfLocal(config);
        rethrow;
      }
    });
  }

  /// Executes a serialized [testConnectionAndSync] pass for [config].
  Future<void> _executeTestConnectionAndSync(WebDavConfig config) async {
    final localizations = lookupAppLocalizations(ref.read(appLocaleProvider));
    if (!config.storageMode.usesWebDav || !config.isWebDavConfigured) {
      final exception = WebDavException(localizations.errorWebDavNotConfigured);
      ref.read(syncStateProvider.notifier).setError(exception.toString());
      throw exception;
    }

    final existingBoard = state.asData?.value;
    await ref.read(webDavConfigProvider.notifier).updateConfig(config);
    try {
      final board = await _runSyncWithStatus(
        config,
        candidateBoard: existingBoard,
        requireTargets: true,
      );
      _conflictWatchDigest = null;
      _lastFailedWatchDigest = null;
      state = AsyncData(board);
    } on TdfSyncOutcomeException {
      await _recordConflictWatchDigestIfLocal(config);
      rethrow;
    }
  }

  /// Serializes and executes a local or remote `.tdf` file wipe for [config].
  Future<void> _executeWipe(
    WebDavConfig config, {
    required bool isRemote,
    required bool createBackup,
    required Future<void> Function() wipeTarget,
  }) async {
    await _awaitInFlightSync();
    final operation = _performWipe(
      config,
      isRemote: isRemote,
      createBackup: createBackup,
      wipeTarget: wipeTarget,
    );
    _inFlightSync = operation;
    try {
      await operation;
    } finally {
      if (identical(_inFlightSync, operation)) {
        _inFlightSync = null;
      }
    }
  }

  /// Awaits any in-flight sync and flushes the populated outgoing [TaskBoard] to local storage.
  Future<void> _flushOutgoingWorkspaceBoard() async {
    await _awaitInFlightSync();
    final currentWorkspace = ref.read(activeWorkspaceProvider).asData?.value;
    final currentBoard = state.asData?.value;
    if (currentWorkspace != null &&
        currentBoard != null &&
        (currentBoard.allTasks.isNotEmpty ||
            currentBoard.labels.isNotEmpty ||
            currentBoard.locations.isNotEmpty)) {
      await TaskSyncPipeline.flushOutgoingLocalBoard(
        ref,
        currentWorkspace,
        currentBoard,
      );
    }
  }

  /// Records conflict state and `_conflictWatchDigest` when [reconcileExternalLocalChanges] encounters [error].
  Future<bool> _handleWatchConflictException({
    required String workspaceId,
    required WebDavConfig config,
    required TdfSyncOutcomeException error,
    required bool localStageSucceeded,
    required String? diskDigest,
  }) async {
    _logWatchError(workspaceId, config.storageMode, error);
    ref.read(syncStateProvider.notifier).setConflict(error.toString());
    if (localStageSucceeded) {
      await _recordConflictWatchDigestIfLocal(config);
      return true;
    }
    _conflictWatchDigest = diskDigest;
    return false;
  }

  /// Returns `true` when [config] enables local directory watching and has a valid local target.
  bool _isExternalWatchActiveForConfig(WebDavConfig config) =>
      config.localWatchEnabled &&
      config.storageMode.usesLocal &&
      config.isLocalConfigured;

  /// Returns `true` when [entry]'s target task, tombstone, or blocked dependents changed between [previousBoard] and [nextBoard].
  bool _isUndoEntryInvalidated(
    TaskUndoEntry entry,
    TaskBoard previousBoard,
    TaskBoard nextBoard,
  ) {
    final taskId = entry.snapshotTask.id;
    if (previousBoard.findTask(taskId) != nextBoard.findTask(taskId)) {
      return true;
    }
    if (previousBoard.deletedBlock.findTaskRecord(taskId) !=
        nextBoard.deletedBlock.findTaskRecord(taskId)) {
      return true;
    }
    return _didAnyDependentChange(
      entry.previouslyBlockedDependentIds,
      previousBoard,
      nextBoard,
    );
  }

  /// Logs a `sync.watch.error` diagnostic event for [workspaceId] and [mode].
  void _logWatchError(String workspaceId, StorageMode mode, Object error) {
    if (!AppLogger.shouldLog(LogLevel.warn)) {
      return;
    }
    AppLogger.event(
      LogLevel.warn,
      LogTag.sync,
      'sync.watch.error',
      fields: <String, Object?>{'workspace': workspaceId, 'mode': mode.name},
      error: error,
    );
  }

  /// Logs a `sync.watch.skip` diagnostic event for [workspaceId] and [reason].
  void _logWatchSkip(String workspaceId, String reason) {
    if (!AppLogger.shouldLog(LogLevel.debug)) {
      return;
    }
    AppLogger.event(
      LogLevel.debug,
      LogTag.sync,
      'sync.watch.skip',
      fields: <String, Object?>{'workspace': workspaceId, 'reason': reason},
    );
  }

  /// Executes a local or remote `.tdf` wipe and preserves opposite-stage synchronization metadata via `copyWith`.
  Future<void> _performWipe(
    WebDavConfig config, {
    required bool isRemote,
    required bool createBackup,
    required Future<void> Function() wipeTarget,
  }) async {
    await ref.read(webDavConfigProvider.notifier).updateConfig(config);
    ref.read(syncStateProvider.notifier).setSyncing();
    try {
      await wipeTarget();
      final workspace = await ref.read(activeWorkspaceProvider.future);
      final settingsRepo = ref.read(settingsRepositoryProvider);
      final currentSyncState = await settingsRepo.loadWorkspaceSyncState(
        workspace.id,
      );
      _pendingDeletedLabelTimestamps.clear();
      _pendingDeletedLocationTimestamps.clear();
      _conflictWatchDigest = null;
      _lastFailedWatchDigest = null;
      _clearUndoStack(isRemote ? 'wipe_remote' : 'wipe_local');
      final WorkspaceSyncState updatedSyncState;
      if (!isRemote) {
        final wipedDigest =
            config.storageMode.usesLocal && config.isLocalConfigured
            ? (await ref.read(localFileRepositoryProvider).readTdfWithDigest())
                  .digest
            : null;
        updatedSyncState = currentSyncState.copyWith(
          clearLastSyncedLocalTdf: true,
          acknowledgedLocalGeneration: 0,
          deletedLabelTimestamps: const <String, DateTime>{},
          deletedLocationTimestamps: const <String, DateTime>{},
          localSourceDigest: wipedDigest,
          clearLocalSourceDigest: wipedDigest == null,
        );
      } else {
        final webDavRepo = ref.read(webDavRepositoryProvider);
        updatedSyncState = currentSyncState.copyWith(
          clearLastSyncedRemoteTdf: true,
          acknowledgedRemoteGeneration: 0,
          deletedLabelTimestamps: const <String, DateTime>{},
          deletedLocationTimestamps: const <String, DateTime>{},
          remoteEtag: webDavRepo.cachedEtag,
          clearRemoteEtag: webDavRepo.cachedEtag == null,
          remoteLastModified: webDavRepo.cachedLastModified,
          clearRemoteLastModified: webDavRepo.cachedLastModified == null,
        );
      }
      await settingsRepo.saveWorkspaceSyncState(workspace.id, updatedSyncState);
      if (!isRemote || !config.storageMode.usesLocal) {
        state = AsyncData(TaskBoard.empty());
      }
      ref.read(syncStateProvider.notifier).setSuccess(DateTime.now());
      AppLogger.info(
        LogTag.sync,
        'Wiped ${isRemote ? 'remote WebDAV' : 'local'} TDF file workspace=${workspace.id} backup=$createBackup',
      );
    } on Object catch (error) {
      ref.read(syncStateProvider.notifier).setError(error.toString());
      rethrow;
    }
  }

  /// Removes invalidated entries from [_undoStack] when external reconciliation modifies target or dependent tasks.
  void _pruneInvalidatedUndoEntries(
    TaskBoard previousBoard,
    TaskBoard nextBoard,
  ) {
    if (_undoStack.isEmpty) {
      return;
    }
    final currentNotice = ref.read(taskUndoStateProvider).latestNotice;
    var noticePruned = false;
    final retained = <TaskUndoEntry>[];
    var prunedCount = 0;
    for (final entry in _undoStack) {
      if (_isUndoEntryInvalidated(entry, previousBoard, nextBoard)) {
        prunedCount++;
        if (currentNotice?.sequence == entry.sequence) {
          noticePruned = true;
        }
      } else {
        retained.add(entry);
      }
    }
    if (prunedCount == 0) {
      return;
    }
    _undoStack
      ..clear()
      ..addAll(retained);
    ref
        .read(taskUndoStateProvider.notifier)
        .update(
          TaskUndoState(
            stackDepth: _undoStack.length,
            latestNotice: noticePruned ? null : currentNotice,
          ),
        );
    if (AppLogger.shouldLog(LogLevel.info)) {
      AppLogger.event(
        LogLevel.info,
        LogTag.domain,
        'task.undo.prune',
        fields: <String, Object?>{
          'pruned': prunedCount,
          'remaining': _undoStack.length,
        },
      );
    }
  }

  /// Reads the local `.tdf` snapshot with digest, retrying once after [localFileWatchReadRetryDelayProvider] on a transient OS file lock.
  Future<({String content, String? digest, bool exists})>
  _readWatchSnapshotWithRetry(String workspaceId) async {
    try {
      return await ref.read(localFileRepositoryProvider).readTdfWithDigest();
    } on LocalFileException catch (error) {
      if (!error.isTransientFileSystemError) {
        rethrow;
      }
      final delay = ref.read(localFileWatchReadRetryDelayProvider);
      if (AppLogger.shouldLog(LogLevel.info)) {
        AppLogger.event(
          LogLevel.info,
          LogTag.sync,
          'sync.watch.retry',
          fields: <String, Object?>{
            'workspace': workspaceId,
            'delay_ms': delay.inMilliseconds,
          },
        );
      }
      await Future<void>.delayed(delay);
      if (!ref.mounted) {
        return (content: '', digest: null, exists: false);
      }
      final activeId = ref.read(activeWorkspaceProvider).asData?.value.id;
      final latestConfig = readCurrentConfig(ref);
      if (activeId != workspaceId ||
          !_isExternalWatchActiveForConfig(latestConfig)) {
        return (content: '', digest: null, exists: false);
      }
      return ref.read(localFileRepositoryProvider).readTdfWithDigest();
    }
  }

  /// Records the current on-disk SHA-256 digest into [_conflictWatchDigest] when local storage is active.
  Future<void> _recordConflictWatchDigestIfLocal(WebDavConfig config) async {
    if (!config.storageMode.usesLocal || !config.isLocalConfigured) {
      return;
    }
    try {
      final snapshot = await ref
          .read(localFileRepositoryProvider)
          .readTdfWithDigest();
      _conflictWatchDigest = snapshot.digest;
    } on LocalFileException {
      // Keep prior conflict digest if reading local storage fails.
    }
  }

  /// Pushes [undoEntry] onto [_undoStack], publishes [TaskUndoState], and returns any evicted oldest entry.
  TaskUndoEntry? _recordOptimisticUndoEntry(TaskUndoEntry undoEntry) {
    _undoWorkspaceId ??= ref.read(activeWorkspaceProvider).asData?.value.id;
    final evicted = _undoStack.length >= TaskBoardUndo.maxUndoEntries
        ? _undoStack.removeFirst()
        : null;
    _undoStack.addLast(undoEntry);
    if (AppLogger.shouldLog(LogLevel.info)) {
      AppLogger.event(
        LogLevel.info,
        LogTag.domain,
        'task.undo.push',
        fields: <String, Object?>{
          'id': undoEntry.snapshotTask.id,
          'kind': undoEntry.kind.name,
          'seq': undoEntry.sequence,
          'depth': _undoStack.length,
        },
      );
    }
    ref
        .read(taskUndoStateProvider.notifier)
        .update(
          TaskUndoState(
            stackDepth: _undoStack.length,
            latestNotice: TaskUndoNotice(
              sequence: undoEntry.sequence,
              kind: undoEntry.kind,
              taskId: undoEntry.snapshotTask.id,
              taskTitle: undoEntry.snapshotTask.title,
            ),
          ),
        );
    return evicted;
  }

  /// Resolves the normalized UTC timestamp and configured local wall-clock timestamp.
  (DateTime utcNow, DateTime localNow) _resolveTimestamps(
    DateTime? currentDate,
  ) => TaskSyncPipeline.resolveTimestamps(ref, currentDate);

  /// Removes [undoEntry] after a local persistence rollback and restores [evictedEntry] if applicable.
  void _rollbackOptimisticUndoEntry(
    TaskUndoEntry undoEntry, {
    required TaskUndoEntry? evictedEntry,
  }) {
    final removed = _undoStack.remove(undoEntry);
    if (removed &&
        evictedEntry != null &&
        _undoStack.length < TaskBoardUndo.maxUndoEntries) {
      _undoStack.addFirst(evictedEntry);
    }
    final currentNotice = ref.read(taskUndoStateProvider).latestNotice;
    final preservedNotice = currentNotice?.sequence == undoEntry.sequence
        ? null
        : currentNotice;
    ref
        .read(taskUndoStateProvider.notifier)
        .update(
          TaskUndoState(
            stackDepth: _undoStack.length,
            latestNotice: preservedNotice,
          ),
        );
    if (AppLogger.shouldLog(LogLevel.warn)) {
      AppLogger.event(
        LogLevel.warn,
        LogTag.domain,
        'task.undo.rollback',
        fields: <String, Object?>{
          'id': undoEntry.snapshotTask.id,
          'kind': undoEntry.kind.name,
          'seq': undoEntry.sequence,
          'direction': 'forward',
        },
      );
    }
  }

  /// Runs the two-stage merge pipeline for an external local `.tdf` edit and isolates Stage 1 vs Stage 2 errors.
  Future<bool> _runExternalWatchSynchronize(
    String workspaceId,
    WebDavConfig config,
    String? diskDigest,
  ) async {
    final existingBoard = state.asData?.value;
    final epoch = _mutationEpoch;
    var localStageSucceeded = false;
    TaskBoard? stage1Board;
    ref.read(syncStateProvider.notifier).setSyncing();
    if (AppLogger.shouldLog(LogLevel.info)) {
      AppLogger.event(
        LogLevel.info,
        LogTag.sync,
        'sync.watch.reconcile',
        fields: <String, Object?>{
          'workspace': workspaceId,
          'mode': config.storageMode.name,
        },
      );
    }
    try {
      final converged = await TaskSyncPipeline.synchronize(
        ref,
        config,
        pendingDeletedLabelTimestamps: _pendingDeletedLabelTimestamps,
        pendingDeletedLocationTimestamps: _pendingDeletedLocationTimestamps,
        candidateBoard: existingBoard ?? TaskBoard.empty(),
        isInitialLoad: existingBoard == null,
        onLocalStageMerged: (mergedBoard) {
          localStageSucceeded = true;
          stage1Board = mergedBoard;
          _lastFailedWatchDigest = null;
          _conflictWatchDigest = null;
          _applyExternalReconciledBoard(
            workspaceId: workspaceId,
            epoch: epoch,
            previousBoard: existingBoard,
            nextBoard: mergedBoard,
          );
        },
      );
      _applyExternalReconciledBoard(
        workspaceId: workspaceId,
        epoch: epoch,
        previousBoard: stage1Board ?? existingBoard,
        nextBoard: converged,
      );
      _lastFailedWatchDigest = null;
      _conflictWatchDigest = null;
      ref
          .read(syncStateProvider.notifier)
          .setSuccess(ref.read(clockProvider)().toUtc());
      return true;
    } on TdfSyncOutcomeException catch (error) {
      return _handleWatchConflictException(
        workspaceId: workspaceId,
        config: config,
        error: error,
        localStageSucceeded: localStageSucceeded,
        diskDigest: diskDigest,
      );
    } on Object catch (error) {
      _logWatchError(workspaceId, config.storageMode, error);
      ref.read(syncStateProvider.notifier).setError(error.toString());
      if (!localStageSucceeded) {
        _lastFailedWatchDigest = diskDigest;
        return false;
      }
      return true;
    }
  }

  /// Wraps [TaskSyncPipeline.runSyncWithStatus] for [config].
  Future<TaskBoard> _runSyncWithStatus(
    WebDavConfig config, {
    TaskBoard? candidateBoard,
    bool isInitialLoad = false,
    bool requireTargets = false,
  }) => TaskSyncPipeline.runSyncWithStatus(
    ref,
    config,
    pendingDeletedLabelTimestamps: _pendingDeletedLabelTimestamps,
    pendingDeletedLocationTimestamps: _pendingDeletedLocationTimestamps,
    candidateBoard: candidateBoard,
    isInitialLoad: isInitialLoad,
    requireTargets: requireTargets,
    onLocalStageMerged: (mergedBoard) {
      state = AsyncData(mergedBoard);
    },
  );

  /// Synchronizes [_undoWorkspaceId] during [build] and clears [_undoStack] when switching workspaces.
  void _syncUndoWorkspaceId(String? workspaceId) {
    if (workspaceId == null) {
      return;
    }
    if (_undoWorkspaceId != null && _undoWorkspaceId != workspaceId) {
      _clearUndoStack('workspace_build', resetProvider: false);
    }
    _undoWorkspaceId = workspaceId;
  }
}

/// Immutable UI notification payload describing the latest recorded undoable action.
@immutable
class TaskUndoNotice {
  /// Creates a [TaskUndoNotice].
  const TaskUndoNotice({
    required this.sequence,
    required this.kind,
    required this.taskId,
    required this.taskTitle,
  });

  /// Category of the recorded action.
  final TaskUndoActionKind kind;

  /// Monotonically increasing session sequence number.
  final int sequence;

  /// Identifier of the affected task.
  final String taskId;

  /// Display title of the affected task at the time of mutation.
  final String taskTitle;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TaskUndoNotice &&
        other.sequence == sequence &&
        other.kind == kind &&
        other.taskId == taskId &&
        other.taskTitle == taskTitle;
  }

  @override
  int get hashCode => Object.hash(sequence, kind, taskId, taskTitle);
}

/// Immutable UI state snapshot for the active workspace's in-memory undo stack.
@immutable
class TaskUndoState {
  /// Creates a [TaskUndoState].
  const TaskUndoState({this.stackDepth = 0, this.latestNotice});

  /// Empty default undo state with zero entries and no active notice.
  static const TaskUndoState empty = TaskUndoState();

  /// Latest undoable mutation notice to present as a `SnackBar`, or `null` when dismissed/cleared.
  final TaskUndoNotice? latestNotice;

  /// Number of undo entries currently retained in `TaskNotifier` (`0..10`).
  final int stackDepth;

  /// Whether at least one action can currently be undone.
  bool get canUndo => stackDepth > 0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TaskUndoState &&
        other.stackDepth == stackDepth &&
        other.latestNotice == latestNotice;
  }

  @override
  int get hashCode => Object.hash(stackDepth, latestNotice);
}

/// Manages the ephemeral [TaskUndoState] for the active workspace.
class TaskUndoStateNotifier extends Notifier<TaskUndoState> {
  @override
  TaskUndoState build() {
    ref.watch(
      activeWorkspaceProvider.select((workspace) => workspace.asData?.value.id),
    );
    return TaskUndoState.empty;
  }

  /// Replaces the current [TaskUndoState] with [next].
  void update(TaskUndoState next) {
    state = next;
  }
}
