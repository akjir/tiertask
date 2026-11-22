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
import '../l10n/tier_localization_extension.dart';
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
  bool _isApplyingUndo = false;
  TaskBoardEvaluationStamp? _lastEvaluationStamp;
  String? _lastFailedWatchDigest;
  String? _lastSelfWipeDigest;
  TaskBoard? _lastSyncedBoard;
  String? _lastSyncedLocalFilePath;
  int _mutationEpoch = 0;
  int _nextUndoSequence = 0;
  TaskBoard? _pendingConflictOriginBoard;
  final ListQueue<TaskUndoEntry> _undoStack = ListQueue<TaskUndoEntry>();
  String? _undoWorkspaceId;

  /// Latest evaluation context stamped by [TaskNotifier] for its published [TaskBoard], or `null` when unavailable.
  TaskBoardEvaluationStamp? get lastEvaluationStamp => _lastEvaluationStamp;

  /// Returns the current [TaskBoard] snapshot or an empty board if not yet loaded.
  TaskBoard get _currentBoard => state.asData?.value ?? TaskBoard.empty();

  /// Returns the active workspace's deadline lead-window duration (`null` when disabled).
  Duration? get _currentDueLeadWindow =>
      readCurrentConfig(ref).dueLeadWindow.duration;

  @override
  Future<TaskBoard> build() async {
    final unregisterUnload = ref
        .read(workspaceUnloadCoordinatorProvider)
        .register(prepareForWorkspaceUnload);
    ref.onDispose(unregisterUnload);
    ref.listen<DueLeadWindow?>(
      webDavConfigProvider.select(
        (asyncConfig) => asyncConfig.asData?.value.dueLeadWindow,
      ),
      _handleDueLeadWindowChanged,
    );
    final workspaceIdFuture = ref.watch(
      activeWorkspaceProvider.selectAsync((workspace) => workspace.id),
    );
    final storageBindingFuture = ref.watch(
      webDavConfigProvider.selectAsync(_storageBindingOf),
    );
    _syncUndoWorkspaceId(ref.read(activeWorkspaceProvider).asData?.value.id);
    _pendingConflictOriginBoard = null;
    _conflictWatchDigest = null;
    _isApplyingUndo = false;
    _lastEvaluationStamp = null;
    _lastFailedWatchDigest = null;
    _lastSelfWipeDigest = null;
    _lastSyncedBoard = null;
    _lastSyncedLocalFilePath = null;
    final (activeWorkspaceId, storageBinding) = await (
      workspaceIdFuture,
      storageBindingFuture,
    ).wait;
    if (!ref.mounted) {
      return TaskBoard.empty();
    }
    final config =
        ref.read(webDavConfigProvider).asData?.value ??
        WebDavConfig(
          filePath: storageBinding.filePath,
          localFilePath: storageBinding.localFilePath,
          password: storageBinding.password,
          serverUrl: storageBinding.serverUrl,
          storageMode: storageBinding.storageMode,
          username: storageBinding.username,
        );
    _syncUndoWorkspaceId(activeWorkspaceId);
    if (!config.hasActiveStorage) {
      return TaskBoard.empty();
    }
    await _awaitInFlightSync();
    if (!_isMountedOnWorkspace(activeWorkspaceId)) {
      return TaskBoard.empty();
    }
    final operation = _runSyncWithStatus(
      config,
      workspaceId: activeWorkspaceId,
      isInitialLoad: true,
    );
    _inFlightSync = operation;
    try {
      final board = await operation;
      if (_isMountedOnWorkspace(activeWorkspaceId)) {
        _stampEvaluatedBoard(
          board,
          evaluatedUtc: ref.read(clockProvider)(),
          config: readCurrentConfig(ref),
        );
        _recordSyncedLocalBoard(board, config);
      }
      return board;
    } on TdfSyncOutcomeException {
      if (_isMountedOnWorkspace(activeWorkspaceId)) {
        await _recordConflictWatchDigestIfLocal(config);
      }
      rethrow;
    } finally {
      if (identical(_inFlightSync, operation)) {
        _inFlightSync = null;
      }
    }
  }

  /// Adds a new TDF `label` block with [name], optional `#RRGGBB` [color], and validated [links] and persists to storage.
  Future<bool> addLabel(
    String name, {
    String? color,
    String? id,
    String? note,
    bool isScoped = false,
    Iterable<TaskLink>? links,
    List<TaskCondition> conditions = const [],
    DateTime? currentDate,
  }) {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    return _commitMutation(
      _currentBoard.addLabel(
        name,
        color: color,
        id: id,
        note: note,
        isScoped: isScoped,
        links: links ?? const <TaskLink>[],
        conditions: conditions,
        currentDate: utcNow,
        localEvaluationTime: localNow,
        timeZone: _resolveTimeZone(utcNow),
        dueLeadWindow: _currentDueLeadWindow,
      ),
    );
  }

  /// Adds a new TDF `location` block with [name], [latitude], [longitude], and [radiusMeters] and persists to storage.
  Future<bool> addLocation(
    String name, {
    required double latitude,
    required double longitude,
    required double radiusMeters,
    String source = 'manual',
    String? id,
    String? note,
    DateTime? currentDate,
  }) {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    return _commitMutation(
      _currentBoard.addLocation(
        name,
        latitude: latitude,
        longitude: longitude,
        radius: radiusMeters,
        source: source,
        id: id,
        note: note,
        currentDate: utcNow,
        localEvaluationTime: localNow,
        timeZone: _resolveTimeZone(utcNow),
        dueLeadWindow: _currentDueLeadWindow,
      ),
    );
  }

  /// Adds a new task to [targetTier] (defaulting to [TaskTier.planned]), runs the
  /// Auto-Pull Cascade, and persists to the active `.tdf` storage backend.
  Future<bool> addTask(
    String title, {
    String? note,
    TaskTier targetTier = TaskTier.planned,
    bool isPriority = false,
    bool subtasksAutoFinish = false,
    List<SubtaskItem> subtasks = const [],
    List<String> labelIds = const [],
    DateTime? dueAt,
    TdfLocalDateTime? dueLocalInput,
    TdfLocalDateTime? dueAnchor,
    bool isDuePassive = false,
    String? dueNote,
    TaskOrigin? origin,
    DateTime? suspendedAt,
    TdfLocalDateTime? suspendedLocalInput,
    bool isSuspendedForever = false,
    String? suspendedNote,
    TaskRepeatRule? repeatRule,
    List<String> blockedByTaskIds = const [],
    List<TdfTaskDependency>? dependencies,
    List<TaskLink> links = const [],
    Iterable<TaskHistoryEntry>? history,
    List<TaskCondition> conditions = const [],
    DateTime? currentDate,
    String? id,
  }) {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    return _commitMutation(
      _currentBoard.addTask(
        title,
        note: note,
        targetTier: targetTier,
        isPriority: isPriority,
        subtasksAutoFinish: subtasksAutoFinish,
        subtasks: subtasks,
        labelIds: labelIds,
        dueAt: dueAt,
        dueLocalInput: dueLocalInput,
        dueAnchor: dueAnchor,
        isDuePassive: isDuePassive,
        dueNote: dueNote,
        origin: origin,
        suspendedAt: suspendedAt,
        suspendedLocalInput: suspendedLocalInput,
        isSuspendedForever: isSuspendedForever,
        suspendedNote: suspendedNote,
        repeatRule: repeatRule,
        blockedByTaskIds: blockedByTaskIds,
        dependencies: dependencies,
        links: links,
        history: history ?? const <TaskHistoryEntry>[],
        conditions: conditions,
        currentDate: utcNow,
        localEvaluationTime: localNow,
        timeZone: _resolveTimeZone(utcNow),
        dueLeadWindow: _currentDueLeadWindow,
        id: id,
      ),
    );
  }

  /// Appends and canonically deduplicates a single [TaskHistoryEntry] on [taskId] and persists to storage when changed.
  Future<bool> addTaskHistoryEntry(
    String taskId, {
    required DateTime timestampUtc,
    required String text,
    DateTime? currentDate,
  }) async {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    final boardBefore = _currentBoard;
    final updatedBoard = boardBefore.addTaskHistoryEntry(
      taskId,
      timestampUtc: timestampUtc,
      text: text,
      currentDate: utcNow,
      localEvaluationTime: localNow,
      timeZone: _resolveTimeZone(utcNow),
      dueLeadWindow: _currentDueLeadWindow,
    );
    if (updatedBoard == boardBefore) {
      return true;
    }
    return _commitMutation(updatedBoard);
  }

  /// Moves an active task immediately to Tier 4 ([TaskTier.blocked]) and persists to storage.
  Future<bool> blockTask(
    String taskId, {
    DateTime? suspendedUntil,
    DateTime? currentDate,
  }) {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    return _commitMutation(
      _currentBoard.blockTask(
        taskId,
        suspendedUntil: suspendedUntil,
        currentDate: utcNow,
        localEvaluationTime: localNow,
        timeZone: _resolveTimeZone(utcNow),
        dueLeadWindow: _currentDueLeadWindow,
      ),
    );
  }

  /// Marks an active task as done in Tier 6 ([TaskTier.completed]), prunes expired tasks,
  /// triggers the Auto-Pull Cascade, and persists to storage.
  Future<bool> completeTask(
    String taskId, {
    int? expectedCompletions,
    DateTime? currentDate,
  }) {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    final boardBefore = _currentBoard;
    final taskBefore = boardBefore.findTask(taskId);
    final updatedBoard = boardBefore.completeTask(
      taskId,
      expectedCompletions: expectedCompletions,
      currentDate: utcNow,
      localEvaluationTime: localNow,
      timeZone: _resolveTimeZone(utcNow),
      dueLeadWindow: _currentDueLeadWindow,
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
            boardAfter: updatedBoard,
          )
        : null;
    return _commitMutation(
      updatedBoard,
      undoEntry: undoEntry,
      evaluatedUtc: utcNow,
    );
  }

  /// Atomically creates a label with [name] and assigns it to [taskId] in a single board persistence cycle.
  Future<TdfLabel?> createLabelAndAssignToTask({
    required String taskId,
    required String name,
    String? color,
    String? id,
    DateTime? currentDate,
  }) async {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    final outcome = _currentBoard.createLabelAndAssignToTask(
      taskId: taskId,
      name: name,
      color: color,
      id: id,
      currentDate: utcNow,
      localEvaluationTime: localNow,
      timeZone: _resolveTimeZone(utcNow),
      dueLeadWindow: _currentDueLeadWindow,
    );
    final createdLabel = outcome.label;
    if (createdLabel == null) {
      return null;
    }
    final committed = await _commitMutation(outcome.board);
    if (!committed) {
      return null;
    }
    return _currentBoard.findLabel(createdLabel.id) ?? createdLabel;
  }

  /// Deletes the label with [labelId], strips its reference from all tasks, and persists to storage.
  Future<bool> deleteLabel(String labelId, {DateTime? currentDate}) {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    return _commitMutation(
      _currentBoard.deleteLabel(
        labelId,
        currentDate: utcNow,
        localEvaluationTime: localNow,
        timeZone: _resolveTimeZone(utcNow),
        dueLeadWindow: _currentDueLeadWindow,
      ),
    );
  }

  /// Deletes the location with [locationId], strips its reference from all tasks and labels, and persists to storage.
  Future<bool> deleteLocation(String locationId, {DateTime? currentDate}) {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    return _commitMutation(
      _currentBoard.deleteLocation(
        locationId,
        currentDate: utcNow,
        localEvaluationTime: localNow,
        timeZone: _resolveTimeZone(utcNow),
        dueLeadWindow: _currentDueLeadWindow,
      ),
    );
  }

  /// Deletes the task with [taskId], removes its `queue` entry, and persists to storage.
  Future<bool> deleteTask(String taskId, {DateTime? currentDate}) {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    final boardBefore = _currentBoard;
    final taskBefore = boardBefore.findTask(taskId);
    final updatedBoard = boardBefore.deleteTask(
      taskId,
      currentDate: utcNow,
      localEvaluationTime: localNow,
      timeZone: _resolveTimeZone(utcNow),
      dueLeadWindow: _currentDueLeadWindow,
    );
    final undoEntry =
        taskBefore != null && updatedBoard.findTask(taskId) == null
        ? TaskBoardUndo.capture(
            sequence: ++_nextUndoSequence,
            kind: TaskUndoActionKind.delete,
            boardBefore: boardBefore,
            taskBefore: taskBefore,
            boardAfter: updatedBoard,
          )
        : null;
    return _commitMutation(
      updatedBoard,
      undoEntry: undoEntry,
      evaluatedUtc: utcNow,
    );
  }

  /// Downgrades an active task per `TDF_SPEC.md` Section 6.3 and persists to storage.
  Future<bool> downgradeTask(
    String taskId, {
    String? activeFilterLabelId,
    DateTime? currentDate,
  }) {
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
      timeZone: _resolveTimeZone(utcNow),
      dueLeadWindow: _currentDueLeadWindow,
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
    return _commitMutation(
      updatedBoard,
      undoEntry: undoEntry,
      evaluatedUtc: utcNow,
      stampEvaluation: activeFilterLabelId == null && locationFix == null,
    );
  }

  /// Moves [taskId] within the shared `queue` block and persists to storage.
  Future<bool> moveTaskInQueue(
    String taskId, {
    String? beforeTaskId,
    String? afterTaskId,
    DateTime? currentDate,
  }) {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    return _commitMutation(
      _currentBoard.moveTaskInQueue(
        taskId,
        beforeTaskId: beforeTaskId,
        afterTaskId: afterTaskId,
        currentDate: utcNow,
        localEvaluationTime: localNow,
        timeZone: _resolveTimeZone(utcNow),
        dueLeadWindow: _currentDueLeadWindow,
      ),
    );
  }

  /// Awaits any in-flight synchronization and flushes the outgoing [TaskBoard] to local storage if populated before switching workspaces.
  Future<void> prepareForWorkspaceUnload() async {
    await _flushOutgoingWorkspaceBoard();
    if (!ref.mounted) {
      return;
    }
    _clearUndoStack('workspace_unload');
  }

  /// Synchronizes and persists the in-memory [board] state across the configured local and WebDAV stages, returning whether it committed locally.
  Future<bool> pushToRemote(
    TaskBoard board, {
    TaskBoard? fallbackBoard,
    Map<String, TdfDeletionResolution> taskConflictResolutions = const {},
    int? mutationEpoch,
  }) async {
    await _awaitInFlightSync();
    if (!ref.mounted) {
      return false;
    }
    final operation = _executePushToRemote(
      board,
      fallbackBoard: fallbackBoard,
      taskConflictResolutions: taskConflictResolutions,
      mutationEpoch: mutationEpoch,
    );
    _inFlightSync = operation;
    try {
      return await operation;
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

  /// Removes a single [TaskHistoryEntry] from [taskId] when present and persists to storage when changed.
  Future<bool> removeTaskHistoryEntry(
    String taskId, {
    required DateTime timestampUtc,
    required String text,
    DateTime? currentDate,
  }) async {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    final boardBefore = _currentBoard;
    final updatedBoard = boardBefore.removeTaskHistoryEntry(
      taskId,
      entry: TaskHistoryEntry(timestampUtc: timestampUtc, text: text),
      currentDate: utcNow,
      localEvaluationTime: localNow,
      timeZone: _resolveTimeZone(utcNow),
      dueLeadWindow: _currentDueLeadWindow,
    );
    if (updatedBoard == boardBefore) {
      return true;
    }
    return _commitMutation(updatedBoard);
  }

  /// Resolves pending `DeletionConflict` items via explicit or bound `Delete` / `Undelete` decisions (`TDF-DEL-003`).
  Future<TaskBoard> resolveDeletionConflicts({
    Map<String, TdfDeletionResolution> taskResolutions = const {},
    Map<String, TdfDeletionResolution> labelResolutions = const {},
    Map<String, TdfDeletionResolution> locationResolutions = const {},
    Map<String, TdfBoundDeletionDecision> boundTaskDecisions = const {},
    Map<String, TdfBoundDeletionDecision> boundLabelDecisions = const {},
    Map<String, TdfBoundDeletionDecision> boundLocationDecisions = const {},
  }) => _executeResolutionSync(
    clearUndoReason: 'resolve_deletion_conflict',
    taskConflictResolutions: taskResolutions,
    labelConflictResolutions: labelResolutions,
    locationConflictResolutions: locationResolutions,
    boundTaskConflictDecisions: boundTaskDecisions,
    boundLabelConflictDecisions: boundLabelDecisions,
    boundLocationConflictDecisions: boundLocationDecisions,
  );

  /// Resolves pending `RecoveryRequired` entities via `discard` or `recoverAsNew` (`TDF-REC-002`).
  Future<TaskBoard> resolveRecovery({
    Map<String, TdfRecoveryResolution> taskResolutions = const {},
    Map<String, TdfRecoveryResolution> labelResolutions = const {},
    Map<String, TdfRecoveryResolution> locationResolutions = const {},
  }) => _executeResolutionSync(
    clearUndoReason: 'resolve_recovery',
    taskRecoveryResolutions: taskResolutions,
    labelRecoveryResolutions: labelResolutions,
    locationRecoveryResolutions: locationResolutions,
  );

  /// Restores a completed task to [targetTier] (defaulting to [TaskTier.planned]) per
  /// `TDF_SPEC.md` Section 6.5 and persists to storage.
  Future<bool> restoreTask(
    String taskId, {
    TaskTier targetTier = TaskTier.planned,
    DateTime? currentDate,
  }) {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    return _commitMutation(
      _currentBoard.restoreTask(
        taskId,
        targetTier: targetTier,
        currentDate: utcNow,
        localEvaluationTime: localNow,
        timeZone: _resolveTimeZone(utcNow),
        dueLeadWindow: _currentDueLeadWindow,
      ),
    );
  }

  /// Schedules a task from `Someday` into the active pull cycle per `TDF_SPEC.md` Section 6.2 and persists to storage.
  Future<bool> scheduleTask(
    String taskId, {
    bool isPriority = false,
    DateTime? currentDate,
  }) {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    return _commitMutation(
      _currentBoard.scheduleTask(
        taskId,
        isPriority: isPriority,
        currentDate: utcNow,
        localEvaluationTime: localNow,
        timeZone: _resolveTimeZone(utcNow),
        dueLeadWindow: _currentDueLeadWindow,
      ),
    );
  }

  /// Switches the active workspace's local `.tdf` file to [newConfig] without moving or deleting the previous file, initializes the target file if missing, and reloads the board.
  Future<void> selectLocalFile(WebDavConfig newConfig) async {
    await _flushOutgoingWorkspaceBoard();
    if (!ref.mounted) {
      return;
    }
    final previousConfig = readCurrentConfig(ref);
    final workspace = await ref.read(activeWorkspaceProvider.future);
    if (!ref.mounted) {
      return;
    }
    final startingWorkspaceId = workspace.id;
    final localizations = lookupAppLocalizations(
      newConfig.language.resolveLocale(PlatformDispatcher.instance.locale),
    );
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final targetRepo = LocalFileRepository(
      config: newConfig,
      baseDirectoryPath: ref.read(localStorageDirectoryPathProvider),
      buildProfile: ref.read(appBuildProfileProvider),
      inMemoryStore: ref.read(inMemoryLocalStoreProvider),
    );
    final targetPath = targetRepo.resolveFilePath();

    try {
      await settingsRepo.saveConfigForWorkspace(startingWorkspaceId, newConfig);
    } on WorkspaceException catch (error) {
      throw LocalFileException(
        localizations.localizeWorkspaceError(error),
        cause: error,
      );
    }
    if (!_isMountedOnWorkspace(startingWorkspaceId)) {
      return;
    }

    try {
      await targetRepo.initializeIfMissing();
    } on Object {
      await settingsRepo.saveConfigForWorkspace(
        startingWorkspaceId,
        previousConfig,
      );
      rethrow;
    }
    if (!_isMountedOnWorkspace(startingWorkspaceId)) {
      return;
    }

    _pendingConflictOriginBoard = null;
    _conflictWatchDigest = null;
    _lastFailedWatchDigest = null;
    _lastSelfWipeDigest = null;
    _lastSyncedBoard = null;
    _lastSyncedLocalFilePath = null;
    _clearUndoStack('select_local_file');
    await TaskSyncPipeline.resetLocalSyncBaseline(ref, startingWorkspaceId);
    if (!_isMountedOnWorkspace(startingWorkspaceId)) {
      return;
    }
    final storageBindingChanged =
        _storageBindingOf(previousConfig) != _storageBindingOf(newConfig);
    await ref.read(webDavConfigProvider.notifier).updateConfig(newConfig);
    AppLogger.info(
      LogTag.sync,
      'Selected local TDF file workspace=$startingWorkspaceId path=$targetPath',
    );
    if (storageBindingChanged || !_isMountedOnWorkspace(startingWorkspaceId)) {
      return;
    }
    final updatedConfig = await ref.read(webDavConfigProvider.future);
    if (!_isMountedOnWorkspace(startingWorkspaceId)) {
      return;
    }
    await _awaitInFlightSync();
    if (!_isMountedOnWorkspace(startingWorkspaceId)) {
      return;
    }
    final operation = _runSyncWithStatus(
      updatedConfig,
      workspaceId: startingWorkspaceId,
      isInitialLoad: true,
    );
    _inFlightSync = operation;
    try {
      final board = await operation;
      if (!_isMountedOnWorkspace(startingWorkspaceId)) {
        return;
      }
      _setEvaluatedState(board, config: updatedConfig);
      _recordSyncedLocalBoard(board, updatedConfig);
    } on TdfSyncOutcomeException {
      if (_isMountedOnWorkspace(startingWorkspaceId)) {
        await _recordConflictWatchDigestIfLocal(updatedConfig);
      }
      rethrow;
    } finally {
      if (identical(_inFlightSync, operation)) {
        _inFlightSync = null;
      }
    }
  }

  /// Synchronizes the in-memory board with the configured local and/or WebDAV storage backends.
  Future<void> syncFromRemote() async {
    await _awaitInFlightSync();
    if (!ref.mounted) {
      return;
    }
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
    if (!ref.mounted) {
      return;
    }
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
  Future<bool> toggleSubtask(
    String taskId,
    int stepIndex, {
    DateTime? currentDate,
  }) {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    final boardBefore = _currentBoard;
    final taskBefore = boardBefore.findTask(taskId);
    final updatedBoard = boardBefore.toggleSubtask(
      taskId,
      stepIndex,
      currentDate: utcNow,
      localEvaluationTime: localNow,
      timeZone: _resolveTimeZone(utcNow),
      dueLeadWindow: _currentDueLeadWindow,
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
            boardAfter: updatedBoard,
          )
        : null;
    return _commitMutation(
      updatedBoard,
      undoEntry: undoEntry,
      evaluatedUtc: utcNow,
    );
  }

  /// Pops and reverses the most recent undoable task mutation when available.
  Future<bool> undoLastAction({
    int? expectedSequence,
    DateTime? currentDate,
  }) async {
    if (_isApplyingUndo || _undoStack.isEmpty) {
      return false;
    }
    if (expectedSequence != null &&
        _undoStack.last.sequence != expectedSequence) {
      return false;
    }
    _isApplyingUndo = true;
    try {
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
        timeZone: _resolveTimeZone(utcNow),
        dueLeadWindow: _currentDueLeadWindow,
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
      final startingWorkspaceId = ref
          .read(activeWorkspaceProvider)
          .asData
          ?.value
          .id;
      final persisted = await _commitMutation(
        outcome.board,
        taskConflictResolutions: outcome.taskConflictResolutions,
      );
      if (!_isMountedOnWorkspace(startingWorkspaceId)) {
        return false;
      }
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
    } finally {
      _isApplyingUndo = false;
    }
  }

  /// Updates an existing label with [labelId] and persists the updated board to storage.
  Future<bool> updateLabel(
    String labelId, {
    String? name,
    String? color,
    bool clearColor = false,
    String? note,
    bool clearNote = false,
    bool? isScoped,
    Iterable<TaskLink>? links,
    List<TaskCondition>? conditions,
    DateTime? currentDate,
  }) {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    return _commitMutation(
      _currentBoard.updateLabel(
        labelId,
        name: name,
        color: color,
        clearColor: clearColor,
        note: note,
        clearNote: clearNote,
        isScoped: isScoped,
        links: links,
        conditions: conditions,
        currentDate: utcNow,
        localEvaluationTime: localNow,
        timeZone: _resolveTimeZone(utcNow),
        dueLeadWindow: _currentDueLeadWindow,
      ),
    );
  }

  /// Updates an existing location with [locationId] and persists the updated board to storage.
  Future<bool> updateLocation(
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
  }) {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    return _commitMutation(
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
        timeZone: _resolveTimeZone(utcNow),
        dueLeadWindow: _currentDueLeadWindow,
      ),
    );
  }

  /// Updates an existing task with [taskId] and persists the updated board to storage.
  Future<bool> updateTask(
    String taskId, {
    String? title,
    String? note,
    TaskTier? targetTier,
    bool? isPriority,
    bool? subtasksAutoFinish,
    List<SubtaskItem>? subtasks,
    List<String>? labelIds,
    DateTime? dueAt,
    TdfLocalDateTime? dueLocalInput,
    TdfLocalDateTime? dueAnchor,
    bool? isDuePassive,
    String? dueNote,
    bool clearDueAt = false,
    bool clearDueAnchor = false,
    bool clearDueNote = false,
    TaskOrigin? origin,
    bool clearOrigin = false,
    DateTime? suspendedAt,
    TdfLocalDateTime? suspendedLocalInput,
    bool? isSuspendedForever,
    String? suspendedNote,
    bool clearSuspendedAt = false,
    bool clearSuspendedNote = false,
    TaskRepeatRule? repeatRule,
    bool clearRepeatRule = false,
    List<String>? blockedByTaskIds,
    List<TdfTaskDependency>? dependencies,
    List<TaskLink>? links,
    Iterable<TaskHistoryEntry>? history,
    List<TaskCondition>? conditions,
    DateTime? currentDate,
  }) {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    return _commitMutation(
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
        dueLocalInput: dueLocalInput,
        dueAnchor: dueAnchor,
        isDuePassive: isDuePassive,
        dueNote: dueNote,
        clearDueAt: clearDueAt,
        clearDueAnchor: clearDueAnchor,
        clearDueNote: clearDueNote,
        origin: origin,
        clearOrigin: clearOrigin,
        suspendedAt: suspendedAt,
        suspendedLocalInput: suspendedLocalInput,
        isSuspendedForever: isSuspendedForever,
        suspendedNote: suspendedNote,
        clearSuspendedAt: clearSuspendedAt,
        clearSuspendedNote: clearSuspendedNote,
        repeatRule: repeatRule,
        clearRepeatRule: clearRepeatRule,
        blockedByTaskIds: blockedByTaskIds,
        dependencies: dependencies,
        links: links,
        history: history,
        conditions: conditions,
        currentDate: utcNow,
        localEvaluationTime: localNow,
        timeZone: _resolveTimeZone(utcNow),
        dueLeadWindow: _currentDueLeadWindow,
      ),
    );
  }

  /// Atomically updates [taskId]'s subtasks and completes [taskId] in one persistence cycle with Undo capture.
  Future<bool> updateTaskAndComplete(
    String taskId, {
    required List<SubtaskItem> subtasks,
    required bool subtasksAutoFinish,
    DateTime? currentDate,
  }) async {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    final boardBefore = _currentBoard;
    final taskBefore = boardBefore.findTask(taskId);
    if (taskBefore == null || taskBefore.isCompleted) {
      return false;
    }
    final completedBoard = boardBefore.updateTaskSubtasksAndComplete(
      taskId,
      subtasks: subtasks,
      subtasksAutoFinish: subtasksAutoFinish,
      currentDate: utcNow,
      localEvaluationTime: localNow,
      timeZone: _resolveTimeZone(utcNow),
      dueLeadWindow: _currentDueLeadWindow,
    );
    final updatedTask = completedBoard.findTask(taskId);
    final undoEntry =
        updatedTask != null && updatedTask.completions > taskBefore.completions
        ? TaskBoardUndo.capture(
            sequence: ++_nextUndoSequence,
            kind: TaskUndoActionKind.complete,
            boardBefore: boardBefore,
            taskBefore: taskBefore,
            boardAfter: completedBoard,
          )
        : null;
    return _commitMutation(
      completedBoard,
      undoEntry: undoEntry,
      evaluatedUtc: utcNow,
    );
  }

  /// Replaces an existing `(oldTimestampUtc, oldText)` history entry on [taskId] and persists to storage when changed.
  Future<bool> updateTaskHistoryEntry(
    String taskId, {
    required DateTime oldTimestampUtc,
    required String oldText,
    required DateTime newTimestampUtc,
    required String newText,
    DateTime? currentDate,
  }) async {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    final boardBefore = _currentBoard;
    final updatedBoard = boardBefore.updateTaskHistoryEntry(
      taskId,
      oldEntry: TaskHistoryEntry(timestampUtc: oldTimestampUtc, text: oldText),
      newTimestampUtc: newTimestampUtc,
      newText: newText,
      currentDate: utcNow,
      localEvaluationTime: localNow,
      timeZone: _resolveTimeZone(utcNow),
      dueLeadWindow: _currentDueLeadWindow,
    );
    if (updatedBoard == boardBefore) {
      return true;
    }
    return _commitMutation(updatedBoard);
  }

  /// Wipes and re-initializes the local `.tdf` file for [config], optionally creating a `.bak` backup first, and resets synchronization baselines.
  Future<void> wipeLocalFile(
    WebDavConfig config, {
    bool createBackup = false,
  }) => _executeWipe(
    config,
    isRemote: false,
    createBackup: createBackup,
    wipeTarget: (localRepo, _) => localRepo.wipeTdf(createBackup: createBackup),
  );

  /// Wipes and re-initializes the remote WebDAV `.tdf` file for [config], optionally creating a `.bak` backup first, and resets synchronization baselines.
  Future<void> wipeRemoteFile(
    WebDavConfig config, {
    bool createBackup = false,
  }) async {
    await _awaitInFlightSync();
    if (!ref.mounted) {
      return;
    }
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
      wipeTarget: (_, webDavRepo) =>
          webDavRepo.wipeTdf(createBackup: createBackup),
    );
  }

  /// Re-evaluates [board] when the active workspace's live [DueLeadWindow] changed from [evaluatedLeadWindow] across an asynchronous gap.
  TaskBoard _alignBoardWithCurrentLeadWindow(
    TaskBoard board,
    DueLeadWindow evaluatedLeadWindow, {
    DateTime? currentDate,
  }) {
    final liveLeadWindow = readCurrentConfig(ref).dueLeadWindow;
    if (liveLeadWindow == evaluatedLeadWindow) {
      return board;
    }
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    return board.applyAutoPull(
      currentDate: utcNow,
      localEvaluationTime: localNow,
      timeZone: _resolveTimeZone(utcNow),
      dueLeadWindow: liveLeadWindow.duration,
    );
  }

  /// Applies [nextBoard] to [state] and selectively prunes [_undoStack] when [workspaceId] and [epoch] remain current.
  void _applyExternalReconciledBoard({
    required String workspaceId,
    required int epoch,
    required TaskBoard? previousBoard,
    required TaskBoard nextBoard,
    required DueLeadWindow evaluatedLeadWindow,
  }) {
    final isActive =
        ref.read(activeWorkspaceProvider).asData?.value.id == workspaceId;
    if (!isActive || epoch != _mutationEpoch) {
      return;
    }
    final alignedBoard = _alignBoardWithCurrentLeadWindow(
      nextBoard,
      evaluatedLeadWindow,
    );
    if (previousBoard == null) {
      _clearUndoStack('external_local_recovery');
    } else if (alignedBoard != previousBoard) {
      _pruneInvalidatedUndoEntries(previousBoard, alignedBoard);
    }
    _setEvaluatedState(alignedBoard);
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
    return _inFlightSync != null || state.hasValue || !state.isLoading;
  }

  /// Clears [_undoStack] for [reason] and optionally resets [taskUndoStateProvider].
  void _clearUndoStack(String reason, {bool resetProvider = true}) {
    final cleared = _undoStack.length;
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
    DateTime? evaluatedUtc,
    bool stampEvaluation = true,
  }) async {
    final startingWorkspaceId = ref
        .read(activeWorkspaceProvider)
        .asData
        ?.value
        .id;
    final epoch = ++_mutationEpoch;
    final previousBoard = _currentBoard;
    if (stampEvaluation) {
      _setEvaluatedState(updatedBoard, evaluatedUtc: evaluatedUtc);
    } else {
      _lastEvaluationStamp = null;
      state = AsyncData(updatedBoard);
    }
    final evictedEntry = undoEntry != null
        ? _recordOptimisticUndoEntry(undoEntry)
        : null;
    final committed = await pushToRemote(
      updatedBoard,
      fallbackBoard: previousBoard,
      taskConflictResolutions: taskConflictResolutions,
      mutationEpoch: epoch,
    );
    if (!committed &&
        undoEntry != null &&
        _isMountedOnWorkspace(startingWorkspaceId)) {
      _rollbackOptimisticUndoEntry(undoEntry, evictedEntry: evictedEntry);
    }
    return committed;
  }

  /// Executes digest-gated reconciliation of an external local `.tdf` file change for [workspaceId].
  Future<bool> _executeExternalLocalReconcile(
    String workspaceId,
    WebDavConfig config,
  ) async {
    final ({String content, String? digest, bool exists}) disk;
    try {
      disk = await _readWatchSnapshotWithRetry(workspaceId, config);
    } on LocalFileException catch (error) {
      if (!ref.mounted) {
        return false;
      }
      _logWatchError(workspaceId, config.storageMode, error);
      final latestConfig = readCurrentConfig(ref);
      final readFailure = await TaskSyncPipeline.buildLocalReadFailureException(
        ref,
        latestConfig,
        localError: error,
      );
      if (!ref.mounted ||
          readFailure == null ||
          !_isSameActiveWatchTarget(workspaceId, config)) {
        return false;
      }
      ref
          .read(syncStateProvider.notifier)
          .setError(readFailure.toString(), fileReadReport: readFailure.report);
      return false;
    } on Object catch (error) {
      if (!ref.mounted || !_isSameActiveWatchTarget(workspaceId, config)) {
        return false;
      }
      _logWatchError(workspaceId, config.storageMode, error);
      ref
          .read(syncStateProvider.notifier)
          .setError(AppLogger.sanitize(error.toString()));
      return false;
    }
    if (!ref.mounted || !_isSameActiveWatchTarget(workspaceId, config)) {
      return false;
    }
    if (!disk.exists || disk.content.trim().isEmpty) {
      _logWatchSkip(workspaceId, 'missing_or_empty');
      return false;
    }
    final WorkspaceSyncState syncState;
    try {
      syncState = await ref
          .read(settingsRepositoryProvider)
          .loadWorkspaceSyncState(workspaceId);
    } on Object catch (error) {
      if (!ref.mounted || !_isSameActiveWatchTarget(workspaceId, config)) {
        return false;
      }
      _logWatchError(workspaceId, config.storageMode, error);
      ref
          .read(syncStateProvider.notifier)
          .setError(AppLogger.sanitize(error.toString()));
      return false;
    }
    if (!ref.mounted || !_isSameActiveWatchTarget(workspaceId, config)) {
      return false;
    }
    final latestConfig = readCurrentConfig(ref);
    final hasOpenConflict = ref.read(syncStateProvider).hasOpenConflict;
    if (!hasOpenConflict) {
      _conflictWatchDigest = null;
    }
    if (disk.digest != null &&
        (disk.digest == syncState.localSourceDigest ||
            disk.digest == _lastSelfWipeDigest)) {
      _lastFailedWatchDigest = null;
      if (hasOpenConflict) {
        _conflictWatchDigest ??= disk.digest;
      }
      _logWatchSkip(workspaceId, 'digest_unchanged');
      return false;
    }
    _lastSelfWipeDigest = null;
    if (hasOpenConflict &&
        disk.digest != null &&
        disk.digest == _conflictWatchDigest) {
      _logWatchSkip(workspaceId, 'open_conflict');
      return false;
    }
    if (disk.digest != null && disk.digest == _lastFailedWatchDigest) {
      _logWatchSkip(workspaceId, 'repeat_failed_digest');
      return false;
    }
    return _runExternalWatchSynchronize(workspaceId, latestConfig, disk.digest);
  }

  /// Executes a single [pushToRemote] persistence pass for [board], returning `true` when persisted locally or no storage backend is active.
  Future<bool> _executePushToRemote(
    TaskBoard board, {
    TaskBoard? fallbackBoard,
    Map<String, TdfDeletionResolution> taskConflictResolutions = const {},
    int? mutationEpoch,
  }) async {
    final workspace = await ref.read(activeWorkspaceProvider.future);
    if (!ref.mounted) {
      return false;
    }
    final WebDavConfig config =
        ref.read(webDavConfigProvider).asData?.value ??
        await ref.read(webDavConfigProvider.future);
    if (!_isMountedOnWorkspace(workspace.id)) {
      return false;
    }
    if (!config.hasActiveStorage) {
      return true;
    }

    var localStageSucceeded = false;
    ref.read(syncStateProvider.notifier).setSyncing();
    try {
      final converged = await TaskSyncPipeline.synchronize(
        ref,
        config,
        workspaceId: workspace.id,
        taskConflictResolutions: taskConflictResolutions,
        candidateBoard: board,
        candidateOriginBoard: _pendingConflictOriginBoard ?? fallbackBoard,
        onLocalStageMerged: (mergedBoard) {
          if (!_isMountedOnWorkspace(workspace.id)) {
            return;
          }
          localStageSucceeded = true;
          _pendingConflictOriginBoard = null;
          _conflictWatchDigest = null;
          _lastFailedWatchDigest = null;
          _lastSelfWipeDigest = null;
          if (mutationEpoch == null || mutationEpoch == _mutationEpoch) {
            _setEvaluatedState(
              _alignBoardWithCurrentLeadWindow(
                mergedBoard,
                config.dueLeadWindow,
              ),
            );
          }
        },
      );
      if (!_isMountedOnWorkspace(workspace.id)) {
        return localStageSucceeded;
      }
      if (taskConflictResolutions.isNotEmpty && mutationEpoch == null) {
        _clearUndoStack('resolve_deletion_conflict');
      }
      final isCurrentEpoch =
          mutationEpoch == null || mutationEpoch == _mutationEpoch;
      if (isCurrentEpoch) {
        final aligned = _alignBoardWithCurrentLeadWindow(
          converged,
          config.dueLeadWindow,
        );
        _setEvaluatedState(aligned);
        _recordSyncedLocalBoard(aligned, config);
      }
      _pendingConflictOriginBoard = null;
      _conflictWatchDigest = null;
      _lastFailedWatchDigest = null;
      _lastSelfWipeDigest = null;
      ref
          .read(syncStateProvider.notifier)
          .setSuccess(ref.read(clockProvider)().toUtc());
      return true;
    } on TdfSyncOutcomeException catch (error) {
      if (!_isMountedOnWorkspace(workspace.id)) {
        return localStageSucceeded;
      }
      if (!localStageSucceeded && mutationEpoch != null) {
        _pendingConflictOriginBoard ??= fallbackBoard;
      }
      if (error.kind == TdfSyncOutcomeKind.syncGenerationRollback) {
        _clearUndoStack('sync_generation_rollback');
      }
      TaskSyncPipeline.logSyncOutcomeEvent(error, config.storageMode);
      ref
          .read(syncStateProvider.notifier)
          .setConflict(
            TaskSyncPipeline.formatSyncOutcomeBanner(ref, error),
            outcome: error,
          );
      await _recordConflictWatchDigestIfLocal(config);
      return localStageSucceeded;
    } on Object catch (error) {
      if (!_isMountedOnWorkspace(workspace.id)) {
        return localStageSucceeded;
      }
      if (!localStageSucceeded) {
        final isCurrentEpoch =
            mutationEpoch == null || mutationEpoch == _mutationEpoch;
        if (isCurrentEpoch && fallbackBoard != null) {
          state = AsyncData(
            _alignBoardWithCurrentLeadWindow(
              fallbackBoard,
              config.dueLeadWindow,
            ),
          );
        }
      }
      ref
          .read(syncStateProvider.notifier)
          .setError(
            error.toString(),
            fileReadReport: error is StorageFileReadException
                ? error.report
                : null,
          );
      return localStageSucceeded;
    }
  }

  /// Serializes and executes an explicit conflict or recovery resolution pass and clears [_undoStack] on success.
  Future<TaskBoard> _executeResolutionSync({
    required String clearUndoReason,
    Map<String, TdfDeletionResolution> taskConflictResolutions = const {},
    Map<String, TdfDeletionResolution> labelConflictResolutions = const {},
    Map<String, TdfDeletionResolution> locationConflictResolutions = const {},
    Map<String, TdfBoundDeletionDecision> boundTaskConflictDecisions = const {},
    Map<String, TdfBoundDeletionDecision> boundLabelConflictDecisions =
        const {},
    Map<String, TdfBoundDeletionDecision> boundLocationConflictDecisions =
        const {},
    Map<String, TdfRecoveryResolution> taskRecoveryResolutions = const {},
    Map<String, TdfRecoveryResolution> labelRecoveryResolutions = const {},
    Map<String, TdfRecoveryResolution> locationRecoveryResolutions = const {},
  }) async {
    await _awaitInFlightSync();
    if (!ref.mounted) {
      return TaskBoard.empty();
    }
    final operation = _performResolutionSync(
      clearUndoReason: clearUndoReason,
      taskConflictResolutions: taskConflictResolutions,
      labelConflictResolutions: labelConflictResolutions,
      locationConflictResolutions: locationConflictResolutions,
      boundTaskConflictDecisions: boundTaskConflictDecisions,
      boundLabelConflictDecisions: boundLabelConflictDecisions,
      boundLocationConflictDecisions: boundLocationConflictDecisions,
      taskRecoveryResolutions: taskRecoveryResolutions,
      labelRecoveryResolutions: labelRecoveryResolutions,
      locationRecoveryResolutions: locationRecoveryResolutions,
    );
    _inFlightSync = operation;
    try {
      return await operation;
    } finally {
      if (identical(_inFlightSync, operation)) {
        _inFlightSync = null;
      }
    }
  }

  /// Executes a serialized [syncFromRemote] pass.
  Future<void> _executeSyncFromRemote() async {
    final workspace = await ref.read(activeWorkspaceProvider.future);
    if (!ref.mounted) {
      return;
    }
    final config = await ref.read(webDavConfigProvider.future);
    if (!_isMountedOnWorkspace(workspace.id)) {
      return;
    }
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
    final epoch = _mutationEpoch;
    final matchesLastSyncedLocal =
        existingBoard != null &&
        identical(existingBoard, _lastSyncedBoard) &&
        config.localFilePath == _lastSyncedLocalFilePath &&
        _pendingConflictOriginBoard == null;
    if (existingBoard == null) {
      state = const AsyncLoading();
    }
    try {
      final board = await _runSyncWithStatus(
        config,
        workspaceId: workspace.id,
        candidateBoard: existingBoard,
        candidateOriginBoard: _pendingConflictOriginBoard,
        candidateMatchesLastSyncedLocal: matchesLastSyncedLocal,
        shouldApplyState: () =>
            epoch == _mutationEpoch && _isMountedOnWorkspace(workspace.id),
      );
      if (!_isMountedOnWorkspace(workspace.id)) {
        return;
      }
      if (existingBoard != null && board != existingBoard) {
        _pruneInvalidatedUndoEntries(existingBoard, board);
      }
      _pendingConflictOriginBoard = null;
      _conflictWatchDigest = null;
      _lastFailedWatchDigest = null;
      _lastSelfWipeDigest = null;
      if (epoch == _mutationEpoch) {
        if (state.asData?.value != board) {
          _setEvaluatedState(board);
        }
        _recordSyncedLocalBoard(state.asData?.value ?? board, config);
      } else if (AppLogger.shouldLog(LogLevel.debug)) {
        AppLogger.event(
          LogLevel.debug,
          LogTag.sync,
          'sync.refresh.stale_epoch',
          fields: <String, Object?>{
            'startedEpoch': epoch,
            'currentEpoch': _mutationEpoch,
          },
        );
      }
    } on TdfSyncOutcomeException catch (error, stackTrace) {
      if (!_isMountedOnWorkspace(workspace.id)) {
        return;
      }
      if (error.kind == TdfSyncOutcomeKind.syncGenerationRollback) {
        _clearUndoStack('sync_generation_rollback');
      }
      await _recordConflictWatchDigestIfLocal(config);
      if (!_isMountedOnWorkspace(workspace.id)) {
        return;
      }
      if (epoch == _mutationEpoch) {
        final fallbackBoard = existingBoard ?? state.asData?.value;
        state = fallbackBoard != null
            ? AsyncData(fallbackBoard)
            : AsyncError(error, stackTrace);
      }
    } on UnsupportedTdfVersionException catch (error, stackTrace) {
      if (!_isMountedOnWorkspace(workspace.id)) {
        return;
      }
      await _recordConflictWatchDigestIfLocal(config);
      if (!_isMountedOnWorkspace(workspace.id)) {
        return;
      }
      if (epoch == _mutationEpoch) {
        final fallbackBoard = existingBoard ?? state.asData?.value;
        state = fallbackBoard != null
            ? AsyncData(fallbackBoard)
            : AsyncError(error, stackTrace);
      }
    } on Object catch (error, stackTrace) {
      if (!_isMountedOnWorkspace(workspace.id)) {
        return;
      }
      if (epoch == _mutationEpoch && existingBoard == null && !state.hasValue) {
        state = AsyncError(error, stackTrace);
      }
    }
  }

  /// Executes a serialized [testConnectionAndSync] pass for [config] before persisting changed credentials.
  Future<void> _executeTestConnectionAndSync(WebDavConfig config) async {
    final localizations = lookupAppLocalizations(ref.read(appLocaleProvider));
    if (!config.storageMode.usesWebDav || !config.isWebDavConfigured) {
      final exception = WebDavException(localizations.errorWebDavNotConfigured);
      ref.read(syncStateProvider.notifier).setError(exception.toString());
      throw exception;
    }

    final workspace = await ref.read(activeWorkspaceProvider.future);
    if (!ref.mounted) {
      return;
    }
    final startingWorkspaceId = workspace.id;
    final existingBoard = state.asData?.value;
    final localRepo = _resolveLocalRepositoryForConfig(config);
    final currentWebDavRepo = ref.read(webDavRepositoryProvider);
    final webDavRepo = _resolveWebDavRepositoryForConfig(
      config,
      current: currentWebDavRepo,
    );
    final ownsTemporaryWebDavRepo = !identical(webDavRepo, currentWebDavRepo);
    try {
      final board = await _runSyncWithStatus(
        config,
        workspaceId: startingWorkspaceId,
        localRepository: localRepo,
        webDavRepository: webDavRepo,
        candidateBoard: existingBoard,
        candidateOriginBoard: _pendingConflictOriginBoard,
        requireTargets: true,
      );
      if (!_isMountedOnWorkspace(startingWorkspaceId)) {
        return;
      }
      if (existingBoard != null && board != existingBoard) {
        _pruneInvalidatedUndoEntries(existingBoard, board);
      }
      _pendingConflictOriginBoard = null;
      _conflictWatchDigest = null;
      _lastFailedWatchDigest = null;
      _lastSelfWipeDigest = null;
      _setEvaluatedState(board, config: config);
      _recordSyncedLocalBoard(board, config);
      if (readCurrentConfig(ref) != config) {
        await ref.read(webDavConfigProvider.notifier).updateConfig(config);
      }
    } on TdfSyncOutcomeException catch (error) {
      if (!_isMountedOnWorkspace(startingWorkspaceId)) {
        rethrow;
      }
      if (error.kind == TdfSyncOutcomeKind.syncGenerationRollback) {
        _clearUndoStack('sync_generation_rollback');
      }
      await _recordConflictWatchDigestIfLocal(config);
      rethrow;
    } finally {
      if (ownsTemporaryWebDavRepo) {
        webDavRepo.close();
      }
    }
  }

  /// Serializes and executes a local or remote `.tdf` file wipe for [config].
  Future<void> _executeWipe(
    WebDavConfig config, {
    required bool isRemote,
    required bool createBackup,
    required Future<void> Function(
      LocalFileRepository localRepo,
      WebDavRepository webDavRepo,
    )
    wipeTarget,
  }) async {
    await _awaitInFlightSync();
    if (!ref.mounted) {
      return;
    }
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
    if (!ref.mounted) {
      return;
    }
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

  /// Re-evaluates the loaded [TaskBoard] in memory without storage I/O when the active workspace's [DueLeadWindow] changes.
  void _handleDueLeadWindowChanged(
    DueLeadWindow? previous,
    DueLeadWindow? next,
  ) {
    if (previous == null || next == null || previous == next) {
      return;
    }
    if (ref.read(activeWorkspaceProvider).asData?.value.id !=
        _undoWorkspaceId) {
      return;
    }
    if (state case AsyncData<TaskBoard>(value: final currentBoard)) {
      final (utcNow, localNow) = _resolveTimestamps(null);
      final reevaluated = currentBoard.applyAutoPull(
        currentDate: utcNow,
        localEvaluationTime: localNow,
        timeZone: _resolveTimeZone(utcNow),
        dueLeadWindow: next.duration,
      );
      _setEvaluatedState(
        reevaluated,
        evaluatedUtc: utcNow,
        config: readCurrentConfig(ref).copyWith(dueLeadWindow: next),
      );
      if (AppLogger.shouldLog(LogLevel.debug)) {
        AppLogger.event(
          LogLevel.debug,
          LogTag.domain,
          'domain.lead_window.reevaluated',
          fields: <String, Object?>{'due_lead': next.name},
        );
      }
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
    if (error.kind == TdfSyncOutcomeKind.syncGenerationRollback) {
      _clearUndoStack('sync_generation_rollback');
    }
    TaskSyncPipeline.logSyncOutcomeEvent(error, config.storageMode);
    ref
        .read(syncStateProvider.notifier)
        .setConflict(
          TaskSyncPipeline.formatSyncOutcomeBanner(ref, error),
          outcome: error,
        );
    if (localStageSucceeded) {
      await _recordConflictWatchDigestIfLocal(config);
      if (!ref.mounted) {
        return false;
      }
      return true;
    }
    _conflictWatchDigest = diskDigest;
    return false;
  }

  /// Returns `true` when the host platform and [config] enable local directory watching for a valid local target.
  bool _isExternalWatchActiveForConfig(WebDavConfig config) =>
      ref.read(supportsLocalFileWatchProvider) &&
      config.localWatchEnabled &&
      config.storageMode.usesLocal &&
      config.isLocalConfigured;

  /// Returns `true` when this notifier is mounted and [workspaceId] remains the active workspace.
  bool _isMountedOnWorkspace(String? workspaceId) {
    if (!ref.mounted) {
      return false;
    }
    if (workspaceId == null) {
      return true;
    }
    return ref.read(activeWorkspaceProvider).asData?.value.id == workspaceId;
  }

  /// Returns `true` when [workspaceId] and [initialConfig]'s local watch target remain active after an asynchronous gap.
  bool _isSameActiveWatchTarget(
    String workspaceId,
    WebDavConfig initialConfig,
  ) {
    final activeId = ref.read(activeWorkspaceProvider).asData?.value.id;
    if (activeId != workspaceId) {
      return false;
    }
    final latestConfig = readCurrentConfig(ref);
    return _isExternalWatchActiveForConfig(latestConfig) &&
        latestConfig.storageMode == initialConfig.storageMode &&
        latestConfig.localFilePath.trim() == initialConfig.localFilePath.trim();
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

  /// Executes a conflict or recovery resolution sync pass and clears [_undoStack] on completion.
  Future<TaskBoard> _performResolutionSync({
    required String clearUndoReason,
    required Map<String, TdfDeletionResolution> taskConflictResolutions,
    required Map<String, TdfDeletionResolution> labelConflictResolutions,
    required Map<String, TdfDeletionResolution> locationConflictResolutions,
    required Map<String, TdfBoundDeletionDecision> boundTaskConflictDecisions,
    required Map<String, TdfBoundDeletionDecision> boundLabelConflictDecisions,
    required Map<String, TdfBoundDeletionDecision>
    boundLocationConflictDecisions,
    required Map<String, TdfRecoveryResolution> taskRecoveryResolutions,
    required Map<String, TdfRecoveryResolution> labelRecoveryResolutions,
    required Map<String, TdfRecoveryResolution> locationRecoveryResolutions,
  }) async {
    final workspace = await ref.read(activeWorkspaceProvider.future);
    if (!ref.mounted) {
      return TaskBoard.empty();
    }
    final WebDavConfig config =
        ref.read(webDavConfigProvider).asData?.value ??
        await ref.read(webDavConfigProvider.future);
    if (!ref.mounted) {
      return TaskBoard.empty();
    }
    if (!config.hasActiveStorage) {
      return _currentBoard;
    }
    try {
      final board = await TaskSyncPipeline.runSyncWithStatus(
        ref,
        config,
        taskConflictResolutions: taskConflictResolutions,
        labelConflictResolutions: labelConflictResolutions,
        locationConflictResolutions: locationConflictResolutions,
        boundTaskConflictDecisions: boundTaskConflictDecisions,
        boundLabelConflictDecisions: boundLabelConflictDecisions,
        boundLocationConflictDecisions: boundLocationConflictDecisions,
        taskRecoveryResolutions: taskRecoveryResolutions,
        labelRecoveryResolutions: labelRecoveryResolutions,
        locationRecoveryResolutions: locationRecoveryResolutions,
        candidateBoard: state.asData?.value,
        candidateOriginBoard: _pendingConflictOriginBoard,
        onLocalStageMerged: (mergedBoard) {
          if (!ref.mounted) {
            return;
          }
          if (ref.read(activeWorkspaceProvider).asData?.value.id ==
              workspace.id) {
            _setEvaluatedState(
              _alignBoardWithCurrentLeadWindow(
                mergedBoard,
                config.dueLeadWindow,
              ),
            );
          }
        },
      );
      if (!ref.mounted) {
        return board;
      }
      _pendingConflictOriginBoard = null;
      _conflictWatchDigest = null;
      _lastFailedWatchDigest = null;
      _lastSelfWipeDigest = null;
      _clearUndoStack(clearUndoReason);
      final aligned = _alignBoardWithCurrentLeadWindow(
        board,
        config.dueLeadWindow,
      );
      if (ref.read(activeWorkspaceProvider).asData?.value.id == workspace.id) {
        _setEvaluatedState(aligned);
        _recordSyncedLocalBoard(aligned, config);
      }
      return aligned;
    } on TdfSyncOutcomeException catch (error) {
      if (!ref.mounted) {
        rethrow;
      }
      if (error.kind == TdfSyncOutcomeKind.syncGenerationRollback) {
        _clearUndoStack('sync_generation_rollback');
      }
      await _recordConflictWatchDigestIfLocal(config);
      rethrow;
    }
  }

  /// Executes a local or remote `.tdf` wipe and preserves opposite-stage synchronization metadata via `copyWith`.
  Future<void> _performWipe(
    WebDavConfig config, {
    required bool isRemote,
    required bool createBackup,
    required Future<void> Function(
      LocalFileRepository localRepo,
      WebDavRepository webDavRepo,
    )
    wipeTarget,
  }) async {
    final workspace = await ref.read(activeWorkspaceProvider.future);
    if (!ref.mounted) {
      return;
    }
    final startingWorkspaceId = workspace.id;
    final localRepo = _resolveLocalRepositoryForConfig(config);
    final currentWebDavRepo = ref.read(webDavRepositoryProvider);
    final webDavRepo = _resolveWebDavRepositoryForConfig(
      config,
      current: currentWebDavRepo,
    );
    final ownsTemporaryWebDavRepo = !identical(webDavRepo, currentWebDavRepo);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    ref.read(syncStateProvider.notifier).setSyncing();
    try {
      await wipeTarget(localRepo, webDavRepo);
      if (!_isMountedOnWorkspace(startingWorkspaceId)) {
        return;
      }
      final currentSyncState = await settingsRepo.loadWorkspaceSyncState(
        startingWorkspaceId,
      );
      if (!_isMountedOnWorkspace(startingWorkspaceId)) {
        return;
      }
      _pendingConflictOriginBoard = null;
      _conflictWatchDigest = null;
      _lastFailedWatchDigest = null;
      _lastSyncedBoard = null;
      _lastSyncedLocalFilePath = null;
      _clearUndoStack(isRemote ? 'wipe_remote' : 'wipe_local');
      final WorkspaceSyncState updatedSyncState;
      if (!isRemote) {
        final wipedDigest =
            config.storageMode.usesLocal && config.isLocalConfigured
            ? (await localRepo.readTdfWithDigest()).digest
            : null;
        if (!_isMountedOnWorkspace(startingWorkspaceId)) {
          return;
        }
        _lastSelfWipeDigest = wipedDigest;
        updatedSyncState = currentSyncState.copyWith(
          clearLastSyncedLocalTdf: true,
          clearAcknowledgedLocalGeneration: true,
          clearLocalSourceDigest: true,
        );
      } else {
        updatedSyncState = currentSyncState.copyWith(
          clearLastSyncedRemoteTdf: true,
          clearAcknowledgedRemoteGeneration: true,
          clearRemoteSourceDigest: true,
          clearRemoteEtag: true,
          clearRemoteLastModified: true,
        );
      }
      await settingsRepo.saveWorkspaceSyncState(
        startingWorkspaceId,
        updatedSyncState,
      );
      if (!_isMountedOnWorkspace(startingWorkspaceId)) {
        return;
      }
      if (!isRemote || !config.storageMode.usesLocal) {
        _setEvaluatedState(TaskBoard.empty());
      }
      ref
          .read(syncStateProvider.notifier)
          .setSuccess(ref.read(clockProvider)().toUtc());
      AppLogger.info(
        LogTag.sync,
        'Wiped ${isRemote ? 'remote WebDAV' : 'local'} TDF file workspace=$startingWorkspaceId backup=$createBackup',
      );
      if (readCurrentConfig(ref) != config) {
        await ref.read(webDavConfigProvider.notifier).updateConfig(config);
      }
    } on Object catch (error) {
      if (_isMountedOnWorkspace(startingWorkspaceId)) {
        ref.read(syncStateProvider.notifier).setError(error.toString());
      }
      rethrow;
    } finally {
      if (ownsTemporaryWebDavRepo) {
        webDavRepo.close();
      }
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
    final (nowUtc, _) = _resolveTimestamps(null);
    final partition = TaskBoardUndo.pruneInvalidatedEntries(
      _undoStack,
      previousBoard: previousBoard,
      nextBoard: nextBoard,
      nowUtc: nowUtc,
    );
    if (partition.pruned.isEmpty) {
      return;
    }
    final currentNotice = ref.read(taskUndoStateProvider).latestNotice;
    final noticePruned =
        currentNotice != null &&
        partition.pruned.any(
          (entry) => entry.sequence == currentNotice.sequence,
        );
    _undoStack
      ..clear()
      ..addAll(partition.retained);
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
          'pruned': partition.pruned.length,
          'remaining': _undoStack.length,
        },
      );
    }
  }

  /// Reads the local `.tdf` snapshot with digest, retrying once after [localFileWatchReadRetryDelayProvider] on a transient OS file lock.
  Future<({String content, String? digest, bool exists})>
  _readWatchSnapshotWithRetry(
    String workspaceId,
    WebDavConfig initialConfig,
  ) async {
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
      if (!ref.mounted ||
          !_isSameActiveWatchTarget(workspaceId, initialConfig)) {
        return (content: '', digest: null, exists: false);
      }
      return ref.read(localFileRepositoryProvider).readTdfWithDigest();
    }
  }

  /// Records the current on-disk SHA-256 digest into [_conflictWatchDigest] when local storage is active.
  Future<void> _recordConflictWatchDigestIfLocal(WebDavConfig config) async {
    if (!ref.mounted ||
        !config.storageMode.usesLocal ||
        !config.isLocalConfigured) {
      return;
    }
    try {
      final snapshot = await ref
          .read(localFileRepositoryProvider)
          .readTdfWithDigest();
      if (!ref.mounted) {
        return;
      }
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

  /// Records [board] as the latest fully converged board for [config]'s local file path.
  void _recordSyncedLocalBoard(TaskBoard board, WebDavConfig config) {
    if (config.storageMode.usesLocal && config.isLocalConfigured) {
      _lastSyncedBoard = board;
      _lastSyncedLocalFilePath = config.localFilePath;
    } else {
      _lastSyncedBoard = null;
      _lastSyncedLocalFilePath = null;
    }
  }

  /// Returns the DI [LocalFileRepository] when its local binding matches [config], or constructs one bound to [config].
  LocalFileRepository _resolveLocalRepositoryForConfig(WebDavConfig config) {
    final current = ref.read(localFileRepositoryProvider);
    if (current.config.localFilePath == config.localFilePath &&
        current.config.storageMode == config.storageMode) {
      return current;
    }
    return LocalFileRepository(
      config: config,
      baseDirectoryPath: ref.read(localStorageDirectoryPathProvider),
      buildProfile: ref.read(appBuildProfileProvider),
      inMemoryStore: ref.read(inMemoryLocalStoreProvider),
    );
  }

  /// Resolves the active workspace [TdfTimeZoneContext] at [utcNow].
  TdfTimeZoneContext _resolveTimeZone(DateTime utcNow) =>
      TaskSyncPipeline.resolveWorkspaceTimeZone(readCurrentConfig(ref), utcNow);

  /// Resolves the normalized UTC timestamp and configured local wall-clock timestamp.
  (DateTime utcNow, DateTime localNow) _resolveTimestamps(
    DateTime? currentDate,
  ) => TaskSyncPipeline.resolveTimestamps(ref, currentDate);

  /// Returns [current] when its remote binding matches [config], or constructs a temporary [WebDavRepository] bound to [config].
  WebDavRepository _resolveWebDavRepositoryForConfig(
    WebDavConfig config, {
    required WebDavRepository current,
  }) {
    if (current.config.serverUrl == config.serverUrl &&
        current.config.username == config.username &&
        current.config.password == config.password &&
        current.config.filePath == config.filePath &&
        current.config.storageMode == config.storageMode) {
      return current;
    }
    return WebDavRepository(config: config);
  }

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
        candidateBoard: existingBoard ?? TaskBoard.empty(),
        candidateOriginBoard: _pendingConflictOriginBoard,
        isInitialLoad: existingBoard == null,
        onLocalStageMerged: (mergedBoard) {
          if (!ref.mounted) {
            return;
          }
          localStageSucceeded = true;
          stage1Board = mergedBoard;
          _pendingConflictOriginBoard = null;
          _lastFailedWatchDigest = null;
          _conflictWatchDigest = null;
          _lastSelfWipeDigest = null;
          _applyExternalReconciledBoard(
            workspaceId: workspaceId,
            epoch: epoch,
            previousBoard: existingBoard,
            nextBoard: mergedBoard,
            evaluatedLeadWindow: config.dueLeadWindow,
          );
        },
      );
      if (!ref.mounted) {
        return false;
      }
      _applyExternalReconciledBoard(
        workspaceId: workspaceId,
        epoch: epoch,
        previousBoard: stage1Board ?? existingBoard,
        nextBoard: converged,
        evaluatedLeadWindow: config.dueLeadWindow,
      );
      if (epoch == _mutationEpoch &&
          ref.read(activeWorkspaceProvider).asData?.value.id == workspaceId) {
        if (state.asData?.value case final current?) {
          _recordSyncedLocalBoard(current, config);
        }
      }
      _pendingConflictOriginBoard = null;
      _lastFailedWatchDigest = null;
      _conflictWatchDigest = null;
      _lastSelfWipeDigest = null;
      ref
          .read(syncStateProvider.notifier)
          .setSuccess(ref.read(clockProvider)().toUtc());
      return true;
    } on TdfSyncOutcomeException catch (error) {
      if (!ref.mounted) {
        return false;
      }
      return _handleWatchConflictException(
        workspaceId: workspaceId,
        config: config,
        error: error,
        localStageSucceeded: localStageSucceeded,
        diskDigest: diskDigest,
      );
    } on Object catch (error) {
      if (!ref.mounted) {
        return false;
      }
      _logWatchError(workspaceId, config.storageMode, error);
      ref
          .read(syncStateProvider.notifier)
          .setError(
            error.toString(),
            fileReadReport: error is StorageFileReadException
                ? error.report
                : null,
          );
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
    String? workspaceId,
    LocalFileRepository? localRepository,
    WebDavRepository? webDavRepository,
    TaskBoard? candidateBoard,
    TaskBoard? candidateOriginBoard,
    bool candidateMatchesLastSyncedLocal = false,
    bool isInitialLoad = false,
    bool requireTargets = false,
    bool Function()? shouldApplyState,
  }) async {
    final board = await TaskSyncPipeline.runSyncWithStatus(
      ref,
      config,
      workspaceId: workspaceId,
      localRepository: localRepository,
      webDavRepository: webDavRepository,
      candidateBoard: candidateBoard,
      candidateOriginBoard: candidateOriginBoard,
      candidateMatchesLastSyncedLocal: candidateMatchesLastSyncedLocal,
      isInitialLoad: isInitialLoad,
      requireTargets: requireTargets,
      onLocalStageMerged: (mergedBoard) {
        if (!_isMountedOnWorkspace(workspaceId)) {
          return;
        }
        if (shouldApplyState != null && !shouldApplyState()) {
          return;
        }
        final aligned = _alignBoardWithCurrentLeadWindow(
          mergedBoard,
          config.dueLeadWindow,
        );
        if (state.asData?.value != aligned) {
          _setEvaluatedState(aligned);
        }
      },
    );
    if (!_isMountedOnWorkspace(workspaceId)) {
      return board;
    }
    return _alignBoardWithCurrentLeadWindow(board, config.dueLeadWindow);
  }

  /// Publishes [board] into [state] and stamps its evaluation context for [evaluatedBoardProvider] reuse.
  void _setEvaluatedState(
    TaskBoard board, {
    DateTime? evaluatedUtc,
    WebDavConfig? config,
  }) {
    _stampEvaluatedBoard(
      board,
      evaluatedUtc: evaluatedUtc ?? ref.read(clockProvider)(),
      config: config ?? readCurrentConfig(ref),
    );
    state = AsyncData(board);
  }

  /// Records [board]'s evaluation timestamp and configuration context for safe zero-copy reuse.
  void _stampEvaluatedBoard(
    TaskBoard board, {
    required DateTime evaluatedUtc,
    required WebDavConfig config,
  }) {
    _lastEvaluationStamp = (
      board: board,
      evaluatedUtc: TaskItem.normalizeTimestamp(evaluatedUtc.toUtc()),
      dueLeadWindow: config.dueLeadWindow,
      timeZoneMode: config.timeZoneMode,
      manualTimeZoneOffsetMinutes: config.manualTimeZoneOffsetMinutes,
    );
  }

  /// Extracts the storage-binding tuple watched by [build] from [config].
  static ({
    String filePath,
    String localFilePath,
    String password,
    String serverUrl,
    StorageMode storageMode,
    String username,
  })
  _storageBindingOf(WebDavConfig config) => (
    filePath: config.filePath,
    localFilePath: config.localFilePath,
    password: config.password,
    serverUrl: config.serverUrl,
    storageMode: config.storageMode,
    username: config.username,
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

/// Evaluation context snapshot captured when [TaskNotifier] publishes an already-evaluated [TaskBoard].
typedef TaskBoardEvaluationStamp = ({
  TaskBoard board,
  DateTime evaluatedUtc,
  DueLeadWindow dueLeadWindow,
  AppTimeZoneMode timeZoneMode,
  int manualTimeZoneOffsetMinutes,
});
