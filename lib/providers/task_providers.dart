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

import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/app_workspace.dart';
import '../models/task_board.dart';
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

/// Provides the [TaskNotifier] managing the in-memory [TaskBoard] and persistence.
final taskNotifierProvider = AsyncNotifierProvider<TaskNotifier, TaskBoard>(
  TaskNotifier.new,
  retry: disableProviderRetry,
);

/// Manages the in-memory [TaskBoard] and synchronizes mutations to local files and WebDAV.
class TaskNotifier extends AsyncNotifier<TaskBoard> {
  Future<void>? _inFlightSync;
  final Map<String, DateTime> _pendingDeletedLabelTimestamps =
      <String, DateTime>{};
  final Map<String, DateTime> _pendingDeletedLocationTimestamps =
      <String, DateTime>{};

  /// Returns the current [TaskBoard] snapshot or an empty board if not yet loaded.
  TaskBoard get _currentBoard => state.asData?.value ?? TaskBoard.empty();

  @override
  Future<TaskBoard> build() async {
    ref
        .read(workspaceUnloadCoordinatorProvider)
        .register(prepareForWorkspaceUnload);
    _pendingDeletedLabelTimestamps.clear();
    _pendingDeletedLocationTimestamps.clear();
    state = const AsyncLoading();
    final config = await ref.watch(webDavConfigProvider.future);
    if (!config.hasActiveStorage) {
      return TaskBoard.empty();
    }
    return _runSyncWithStatus(config, isInitialLoad: true);
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
    await _commitMutation(
      _currentBoard.completeTask(
        taskId,
        expectedCompletions: expectedCompletions,
        currentDate: utcNow,
        localEvaluationTime: localNow,
      ),
    );
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
    await _commitMutation(
      _currentBoard.deleteTask(
        taskId,
        currentDate: utcNow,
        localEvaluationTime: localNow,
      ),
    );
  }

  /// Downgrades an active task per `TDF_SPEC.md` Section 6.3 and persists to storage.
  Future<void> downgradeTask(
    String taskId, {
    String? activeFilterLabelId,
    DateTime? currentDate,
  }) async {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    final locationFix = ref.read(locationStateProvider).fix;
    await _commitMutation(
      _currentBoard.downgradeTask(
        taskId,
        activeLabelId: activeFilterLabelId,
        currentLatitude: locationFix?.latitude,
        currentLongitude: locationFix?.longitude,
        currentDate: utcNow,
        localEvaluationTime: localNow,
      ),
    );
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

  /// Synchronizes and persists the in-memory [board] state across the configured local and WebDAV stages.
  Future<void> pushToRemote(TaskBoard board, {TaskBoard? fallbackBoard}) async {
    await _awaitInFlightSync();
    final operation = _executePushToRemote(board, fallbackBoard: fallbackBoard);
    _inFlightSync = operation;
    try {
      await operation;
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
    await prepareForWorkspaceUnload();
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
    await TaskSyncPipeline.resetLocalSyncBaseline(ref, workspace.id);
    await ref.read(webDavConfigProvider.notifier).updateConfig(newConfig);
    final updatedConfig = await ref.read(webDavConfigProvider.future);
    state = AsyncData(
      await _runSyncWithStatus(updatedConfig, isInitialLoad: true),
    );
    AppLogger.info(
      LogTag.sync,
      'Selected local TDF file workspace=${workspace.id} path=$targetPath',
    );
  }

  /// Synchronizes the in-memory board with the configured local and/or WebDAV storage backends.
  Future<void> syncFromRemote() async {
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
    state = await AsyncValue.guard(
      () => _runSyncWithStatus(config, candidateBoard: existingBoard),
    );
  }

  /// Tests storage access using [config], runs the two-stage merge pipeline, and updates the board.
  Future<void> testConnectionAndSync(WebDavConfig config) async {
    final localizations = lookupAppLocalizations(ref.read(appLocaleProvider));
    if (!config.storageMode.usesWebDav || !config.isWebDavConfigured) {
      final exception = WebDavException(localizations.errorWebDavNotConfigured);
      ref.read(syncStateProvider.notifier).setError(exception.toString());
      throw exception;
    }

    final existingBoard = state.asData?.value;
    await ref.read(webDavConfigProvider.notifier).updateConfig(config);
    state = AsyncData(
      await _runSyncWithStatus(
        config,
        candidateBoard: existingBoard,
        requireTargets: true,
      ),
    );
  }

  /// Toggles the subtask step at [stepIndex] on [taskId] and persists to storage.
  Future<void> toggleSubtask(
    String taskId,
    int stepIndex, {
    DateTime? currentDate,
  }) async {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    await _commitMutation(
      _currentBoard.toggleSubtask(
        taskId,
        stepIndex,
        currentDate: utcNow,
        localEvaluationTime: localNow,
      ),
    );
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

  /// Awaits any currently running synchronization operation without propagating its exception.
  Future<void> _awaitInFlightSync() async {
    if (_inFlightSync case final pending?) {
      try {
        await pending;
      } on Object {
        // Proceed after in-flight sync finishes.
      }
    }
  }

  /// Updates the in-memory board state and executes the two-stage persistence pipeline, rolling back on local failure.
  Future<void> _commitMutation(TaskBoard updatedBoard) async {
    final previousBoard = _currentBoard;
    state = AsyncData(updatedBoard);
    await pushToRemote(updatedBoard, fallbackBoard: previousBoard);
  }

  /// Executes a single [pushToRemote] persistence pass for [board].
  Future<void> _executePushToRemote(
    TaskBoard board, {
    TaskBoard? fallbackBoard,
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
        candidateBoard: board,
        onLocalStageMerged: (mergedBoard) {
          localStageSucceeded = true;
          state = AsyncData(mergedBoard);
        },
      );
      if (ref.read(activeWorkspaceProvider).asData?.value.id == workspace.id) {
        state = AsyncData(converged);
      }
      ref.read(syncStateProvider.notifier).setSuccess(DateTime.now());
    } on Object catch (error) {
      if (!localStageSucceeded &&
          fallbackBoard != null &&
          ref.read(activeWorkspaceProvider).asData?.value.id == workspace.id) {
        state = AsyncData(fallbackBoard);
      }
      ref.read(syncStateProvider.notifier).setError(error.toString());
    }
  }

  /// Executes a local or remote `.tdf` file wipe for [config] and resets workspace synchronization baselines.
  Future<void> _executeWipe(
    WebDavConfig config, {
    required bool isRemote,
    required bool createBackup,
    required Future<void> Function() wipeTarget,
  }) async {
    await _awaitInFlightSync();
    await ref.read(webDavConfigProvider.notifier).updateConfig(config);
    ref.read(syncStateProvider.notifier).setSyncing();
    try {
      await wipeTarget();
      final workspace = await ref.read(activeWorkspaceProvider.future);
      _pendingDeletedLabelTimestamps.clear();
      _pendingDeletedLocationTimestamps.clear();
      await ref
          .read(settingsRepositoryProvider)
          .saveWorkspaceSyncState(workspace.id, WorkspaceSyncState.empty);
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

  /// Resolves the normalized UTC timestamp and configured local wall-clock timestamp.
  (DateTime utcNow, DateTime localNow) _resolveTimestamps(
    DateTime? currentDate,
  ) => TaskSyncPipeline.resolveTimestamps(ref, currentDate);

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
}
