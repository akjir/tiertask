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

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/app_workspace.dart';
import '../models/task_board.dart';
import '../models/task_board_sync.dart';
import '../models/task_item.dart';
import '../models/task_tier.dart';
import '../models/tdf_metadata.dart';
import '../models/webdav_config.dart';
import '../repositories/local_file_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/webdav_repository.dart';
import '../services/tdf_service.dart';
import '../ui/app_theme.dart';
import 'workspace_providers.dart';

/// Provides the effective [Locale] (`en` or `de`) based on [webDavConfigProvider] and OS locale.
final appLocaleProvider = Provider<Locale>((ref) {
  final language = _resolveCurrentConfig(ref).language;
  return language.resolveLocale(PlatformDispatcher.instance.locale);
});

/// Provides the selected [AppThemeMode] (`system`, `light`, or `dark`) from [webDavConfigProvider].
final appThemeModeProvider = Provider<AppThemeMode>((ref) {
  return _resolveCurrentConfig(ref).themeMode;
});

/// Provides the selected [AppThemePalette] (`slate` or `navy`) from [webDavConfigProvider].
final appThemePaletteProvider = Provider<AppThemePalette>((ref) {
  return _resolveCurrentConfig(ref).themePalette;
});

/// Provides the active [AppThemeSet] (`light` and `dark` [AppTheme] pair) replaceable at runtime.
final appThemeProvider = NotifierProvider<AppThemeNotifier, AppThemeSet>(
  AppThemeNotifier.new,
);

/// Injectable clock function for deterministic date handling in unit tests.
final clockProvider = Provider<DateTime Function()>((ref) {
  return DateTime.now;
});

/// Provides the native directory picker function, overridable in widget tests.
final directoryPickerProvider =
    Provider<Future<String?> Function({String? initialDirectory})>((ref) {
      return ({String? initialDirectory}) => ref
          .read(localFileRepositoryProvider)
          .pickDirectory(initialDirectory: initialDirectory);
    });

/// Provides a [LocalFileRepository] configured with the current [WebDavConfig].
final localFileRepositoryProvider = Provider<LocalFileRepository>((ref) {
  final config = _resolveCurrentConfig(ref);
  final baseDirectoryPath = ref.watch(localStorageDirectoryPathProvider);
  final inMemoryStore = ref.watch(_inMemoryLocalStoreProvider);
  return LocalFileRepository(
    config: config,
    baseDirectoryPath: baseDirectoryPath,
    inMemoryStore: inMemoryStore,
  );
});

/// Optional base directory path override for [LocalFileRepository] in tests.
final localStorageDirectoryPathProvider = Provider<String?>((ref) {
  return null;
});

/// Provides the [SettingsRepository] for loading and saving application settings.
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SecureSettingsRepository();
});

/// Whether the host platform supports changing the local `.tdf` directory via a native picker (`true` on Linux and Windows, `false` on Android).
final supportsDirectoryPickerProvider = Provider<bool>((ref) {
  return defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows;
});

/// Provides the current [SyncState] for local and WebDAV persistence operations.
final syncStateProvider = NotifierProvider<SyncStateNotifier, SyncState>(
  SyncStateNotifier.new,
);

/// Provides the [TaskNotifier] managing the in-memory [TaskBoard] and persistence.
final taskNotifierProvider = AsyncNotifierProvider<TaskNotifier, TaskBoard>(
  TaskNotifier.new,
);

/// Provides the stateless [TdfService] scanner, parser, and serializer.
final tdfServiceProvider = Provider<TdfService>((ref) {
  return const TdfService();
});

/// Provides the persisted [WebDavConfig] state.
final webDavConfigProvider =
    AsyncNotifierProvider<WebDavConfigNotifier, WebDavConfig>(
      WebDavConfigNotifier.new,
    );

/// Provides a [WebDavRepository] configured with the current [WebDavConfig].
final webDavRepositoryProvider = Provider<WebDavRepository>((ref) {
  final config = _resolveCurrentConfig(ref);
  return WebDavRepository(config: config);
});

/// Provides an isolated in-memory file map for hermetic widget tests.
final _inMemoryLocalStoreProvider = Provider<Map<String, String>>((ref) {
  return <String, String>{};
});

/// Manages the active [AppThemeSet] and supports swapping themes at runtime.
class AppThemeNotifier extends Notifier<AppThemeSet> {
  @override
  AppThemeSet build() {
    final palette = ref.watch(appThemePaletteProvider);
    return AppThemeSet.forPalette(palette);
  }

  /// Replaces both light and dark themes with a single [theme] at runtime.
  void setTheme(AppTheme theme) {
    state = AppThemeSet.uniform(theme);
  }

  /// Replaces the active [AppThemeSet] (`light` and `dark` pair) at runtime.
  void setThemeSet(AppThemeSet themeSet) {
    state = themeSet;
  }
}

/// Represents the current synchronization state for local and WebDAV storage.
class SyncState {
  /// Creates a [SyncState] snapshot.
  const SyncState({
    this.isSyncing = false,
    this.lastSyncedAt,
    this.errorMessage,
  });

  /// Optional error message from the most recent synchronization attempt.
  final String? errorMessage;

  /// Whether a synchronization request is currently in flight.
  final bool isSyncing;

  /// Timestamp of the last successful synchronization.
  final DateTime? lastSyncedAt;

  /// Returns a copy of this [SyncState] with updated fields.
  SyncState copyWith({
    bool? isSyncing,
    DateTime? lastSyncedAt,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Manages [SyncState] updates during local and WebDAV load and save operations.
class SyncStateNotifier extends Notifier<SyncState> {
  @override
  SyncState build() {
    ref.watch(
      activeWorkspaceProvider.select((workspace) => workspace.asData?.value.id),
    );
    return const SyncState();
  }

  /// Clears any active synchronization error banner.
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Records a synchronization failure with [message].
  void setError(String message) {
    state = state.copyWith(isSyncing: false, errorMessage: message);
  }

  /// Records a successful synchronization at [timestamp].
  void setSuccess(DateTime timestamp) {
    state = SyncState(
      isSyncing: false,
      lastSyncedAt: timestamp,
      errorMessage: null,
    );
  }

  /// Marks synchronization as in progress and clears previous errors.
  void setSyncing() {
    state = state.copyWith(isSyncing: true, clearError: true);
  }
}

/// Manages the in-memory [TaskBoard] and synchronizes mutations to local files and WebDAV.
class TaskNotifier extends AsyncNotifier<TaskBoard> {
  Future<void>? _inFlightSync;
  final Map<String, DateTime> _pendingDeletedLabelTimestamps =
      <String, DateTime>{};

  TaskBoard get _currentBoard => state.asData?.value ?? TaskBoard.empty();

  @override
  Future<TaskBoard> build() async {
    ref
        .read(workspaceUnloadCoordinatorProvider)
        .register(prepareForWorkspaceUnload);
    _pendingDeletedLabelTimestamps.clear();
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
    DateTime? currentDate,
  }) async {
    final (utcNow, _) = _resolveTimestamps(currentDate);
    final updated = _currentBoard.addLabel(
      name,
      color: color,
      id: id,
      note: note,
      currentDate: utcNow,
    );
    await _commitMutation(updated);
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
    DateTime? suspendedAt,
    TaskRepeatRule? repeatRule,
    List<String> blockedByTaskIds = const [],
    List<TaskCondition> conditions = const [],
    DateTime? currentDate,
    String? id,
  }) async {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    final updated = _currentBoard.addTask(
      title,
      note: note,
      targetTier: targetTier,
      isPriority: isPriority,
      subtasksAutoFinish: subtasksAutoFinish,
      subtasks: subtasks,
      labelIds: labelIds,
      suspendedAt: suspendedAt,
      repeatRule: repeatRule,
      blockedByTaskIds: blockedByTaskIds,
      conditions: conditions,
      currentDate: utcNow,
      localEvaluationTime: localNow,
      id: id,
    );
    await _commitMutation(updated);
  }

  /// Marks an active task as done in Tier 6 ([TaskTier.completed]), prunes expired tasks,
  /// triggers the Auto-Pull Cascade, and persists to storage.
  Future<void> completeTask(String taskId, {DateTime? currentDate}) async {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    final updated = _currentBoard.completeTask(
      taskId,
      currentDate: utcNow,
      localEvaluationTime: localNow,
    );
    await _commitMutation(updated);
  }

  /// Deletes the label with [labelId], strips its reference from all tasks, and persists to storage.
  Future<void> deleteLabel(String labelId, {DateTime? currentDate}) async {
    final (utcNow, _) = _resolveTimestamps(currentDate);
    final existingLabel = _currentBoard.labels
        .where((label) => label.id == labelId)
        .firstOrNull;
    final deleteTimestamp = TaskItem.nextModifiedTimestamp(
      existingLabel?.effectiveModifiedAt ?? TdfLabel.defaultModifiedAt,
      utcNow,
    );
    _pendingDeletedLabelTimestamps[labelId] = deleteTimestamp;
    await _persistPendingLabelDeletion(labelId, deleteTimestamp);
    final updated = _currentBoard.deleteLabel(labelId, currentDate: utcNow);
    await _commitMutation(updated);
  }

  /// Downgrades an active task per `TDF_SPEC.md` Section 6.3 and persists to storage.
  Future<void> downgradeTask(String taskId, {DateTime? currentDate}) async {
    final (utcNow, _) = _resolveTimestamps(currentDate);
    final updated = _currentBoard.downgradeTask(taskId, currentDate: utcNow);
    await _commitMutation(updated);
  }

  /// Awaits any in-flight synchronization and flushes the outgoing [TaskBoard] to local storage if populated before switching workspaces.
  Future<void> prepareForWorkspaceUnload() async {
    if (_inFlightSync case final pending?) {
      try {
        await pending;
      } on Object {
        // Proceed with local flush.
      }
    }
    final currentWorkspace = ref.read(activeWorkspaceProvider).asData?.value;
    final currentBoard = state.asData?.value;
    if (currentWorkspace != null &&
        currentBoard != null &&
        (currentBoard.allTasks.isNotEmpty || currentBoard.labels.isNotEmpty)) {
      await _flushOutgoingLocalBoard(currentWorkspace, currentBoard);
    }
  }

  /// Synchronizes and persists the in-memory [board] state across the configured local and WebDAV stages.
  Future<void> pushToRemote(TaskBoard board) async {
    if (_inFlightSync case final pending?) {
      try {
        await pending;
      } on Object {
        // Continue with next mutation sync.
      }
    }
    final operation = _executePushToRemote(board);
    _inFlightSync = operation;
    try {
      await operation;
    } finally {
      if (identical(_inFlightSync, operation)) {
        _inFlightSync = null;
      }
    }
  }

  /// Updates the display [name] of the label with [labelId] and persists to storage.
  Future<void> renameLabel(
    String labelId,
    String name, {
    DateTime? currentDate,
  }) async {
    final (utcNow, _) = _resolveTimestamps(currentDate);
    final updated = _currentBoard.renameLabel(
      labelId,
      name,
      currentDate: utcNow,
    );
    await _commitMutation(updated);
  }

  /// Restores a completed task to [targetTier] (defaulting to [TaskTier.planned]) per
  /// `TDF_SPEC.md` Section 6.5 and persists to storage.
  Future<void> restoreTask(
    String taskId, {
    TaskTier targetTier = TaskTier.planned,
    DateTime? currentDate,
  }) async {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    final updated = _currentBoard.restoreTask(
      taskId,
      targetTier: targetTier,
      currentDate: utcNow,
      localEvaluationTime: localNow,
    );
    await _commitMutation(updated);
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
    final converged = await _runSyncWithStatus(
      config,
      candidateBoard: existingBoard,
      requireTargets: true,
    );
    state = AsyncData(converged);
  }

  /// Toggles the subtask step at [stepIndex] on [taskId] and persists to storage.
  Future<void> toggleSubtask(
    String taskId,
    int stepIndex, {
    DateTime? currentDate,
  }) async {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    final updated = _currentBoard.toggleSubtask(
      taskId,
      stepIndex,
      currentDate: utcNow,
      localEvaluationTime: localNow,
    );
    await _commitMutation(updated);
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
    DateTime? suspendedAt,
    bool clearSuspendedAt = false,
    TaskRepeatRule? repeatRule,
    bool clearRepeatRule = false,
    List<String>? blockedByTaskIds,
    List<TaskCondition>? conditions,
    DateTime? currentDate,
  }) async {
    final (utcNow, localNow) = _resolveTimestamps(currentDate);
    final updated = _currentBoard.updateTask(
      taskId,
      title: title,
      note: note,
      targetTier: targetTier,
      isPriority: isPriority,
      subtasksAutoFinish: subtasksAutoFinish,
      subtasks: subtasks,
      labelIds: labelIds,
      suspendedAt: suspendedAt,
      clearSuspendedAt: clearSuspendedAt,
      repeatRule: repeatRule,
      clearRepeatRule: clearRepeatRule,
      blockedByTaskIds: blockedByTaskIds,
      conditions: conditions,
      currentDate: utcNow,
      localEvaluationTime: localNow,
    );
    await _commitMutation(updated);
  }

  /// Updates the in-memory board state and executes the two-stage persistence pipeline.
  Future<void> _commitMutation(TaskBoard updatedBoard) async {
    state = AsyncData(updatedBoard);
    await pushToRemote(updatedBoard);
  }

  /// Executes a single [pushToRemote] persistence pass for [board].
  Future<void> _executePushToRemote(TaskBoard board) async {
    final workspace = await ref.read(activeWorkspaceProvider.future);
    final WebDavConfig config =
        ref.read(webDavConfigProvider).asData?.value ??
        await ref.read(webDavConfigProvider.future);
    if (!config.hasActiveStorage) {
      return;
    }

    ref.read(syncStateProvider.notifier).setSyncing();
    try {
      final converged = await _synchronizePipeline(
        config,
        candidateBoard: board,
      );
      if (ref.read(activeWorkspaceProvider).asData?.value.id == workspace.id) {
        state = AsyncData(converged);
      }
      ref.read(syncStateProvider.notifier).setSuccess(DateTime.now());
    } on Object catch (error) {
      ref.read(syncStateProvider.notifier).setError(error.toString());
    }
  }

  /// Flushes [board] to the local `.tdf` file of [workspace] before unloading when local persistence is enabled.
  Future<void> _flushOutgoingLocalBoard(
    AppWorkspace workspace,
    TaskBoard board,
  ) async {
    final config = workspace.config;
    if (!config.storageMode.usesLocal || !config.isLocalConfigured) {
      return;
    }
    try {
      final serialized = _serializeTdf(board);
      await ref.read(localFileRepositoryProvider).saveTdf(serialized);
    } on Object {
      // Best-effort flush before workspace unload.
    }
  }

  /// Parses [rawTdf] using [utcNow] and [localNow].
  TaskBoard _parseTdf(String rawTdf, DateTime utcNow, DateTime localNow) {
    return ref
        .read(tdfServiceProvider)
        .parse(rawTdf, evaluationTime: utcNow, localEvaluationTime: localNow);
  }

  /// Immediately persists a label deletion timestamp to [WorkspaceSyncState] so offline restarts preserve it.
  Future<void> _persistPendingLabelDeletion(
    String labelId,
    DateTime deletedAt,
  ) async {
    final workspace = await ref.read(activeWorkspaceProvider.future);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final currentSyncState = await settingsRepo.loadWorkspaceSyncState(
      workspace.id,
    );
    final updatedDeleted = <String, DateTime>{
      ...currentSyncState.deletedLabelTimestamps,
      labelId: deletedAt,
    };
    await settingsRepo.saveWorkspaceSyncState(
      workspace.id,
      currentSyncState.copyWith(deletedLabelTimestamps: updatedDeleted),
    );
  }

  /// Resolves the normalized UTC timestamp and configured local wall-clock timestamp.
  (DateTime utcNow, DateTime localNow) _resolveTimestamps(
    DateTime? currentDate,
  ) {
    final rawClock = currentDate ?? ref.read(clockProvider)();
    final utcNow = TaskItem.normalizeTimestamp(rawClock.toUtc());
    final config = _resolveCurrentConfig(ref);
    final localNow = config.toLocalWallClock(utcNow);
    return (utcNow, localNow);
  }

  /// Wraps [_synchronizePipeline] with [SyncStateNotifier] status updates.
  Future<TaskBoard> _runSyncWithStatus(
    WebDavConfig config, {
    TaskBoard? candidateBoard,
    bool isInitialLoad = false,
    bool requireTargets = false,
  }) async {
    ref.read(syncStateProvider.notifier).setSyncing();
    try {
      final board = await _synchronizePipeline(
        config,
        candidateBoard: candidateBoard,
        isInitialLoad: isInitialLoad,
        requireTargets: requireTargets,
      );
      ref.read(syncStateProvider.notifier).setSuccess(DateTime.now());
      return board;
    } on Object catch (error) {
      ref.read(syncStateProvider.notifier).setError(error.toString());
      rethrow;
    }
  }

  /// Serializes [board] into canonical `.tdf` text.
  String _serializeTdf(TaskBoard board) {
    return ref.read(tdfServiceProvider).serialize(board);
  }

  /// Executes the two-stage merge pipeline (`In-Memory <-> Local File <-> WebDAV`).
  Future<TaskBoard> _synchronizePipeline(
    WebDavConfig config, {
    TaskBoard? candidateBoard,
    bool isInitialLoad = false,
    bool requireTargets = false,
  }) async {
    final (utcNow, localNow) = _resolveTimestamps(null);
    final workspace = await ref.read(activeWorkspaceProvider.future);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    var syncState = await settingsRepo.loadWorkspaceSyncState(workspace.id);
    final deletedLabels = <String, DateTime>{
      ...syncState.deletedLabelTimestamps,
      ..._pendingDeletedLabelTimestamps,
    };

    var hasWorkingBoard = candidateBoard != null && !isInitialLoad;
    var workingBoard = candidateBoard ?? TaskBoard.empty();

    if (config.storageMode.usesLocal &&
        (requireTargets || config.isLocalConfigured)) {
      final rawLocal = await ref.read(localFileRepositoryProvider).loadTdf();
      final hasLocalContent = rawLocal.trim().isNotEmpty;
      if (hasLocalContent) {
        final localBoard = _parseTdf(rawLocal, utcNow, localNow);
        final localBaseline = _tryParseBaseline(
          syncState.lastSyncedLocalTdf,
          utcNow,
          localNow,
        );
        workingBoard = TaskBoardSync.merge(
          primary: hasWorkingBoard ? workingBoard : localBoard,
          secondary: localBoard,
          baseline: localBaseline ?? (hasWorkingBoard ? null : localBoard),
          deletedLabelTimestamps: deletedLabels,
          evaluationTime: utcNow,
          localEvaluationTime: localNow,
        );
        hasWorkingBoard = true;
      }
      if (hasLocalContent || hasWorkingBoard || requireTargets) {
        workingBoard = TaskBoardSync.stampAndNormalize(
          workingBoard,
          evaluationTime: utcNow,
          localEvaluationTime: localNow,
        );
        final serializedLocal = _serializeTdf(workingBoard);
        if (requireTargets ||
            candidateBoard != null ||
            rawLocal.trim() != serializedLocal.trim()) {
          await ref.read(localFileRepositoryProvider).saveTdf(serializedLocal);
        }
        syncState = syncState.copyWith(
          lastSyncedLocalTdf: serializedLocal,
          deletedLabelTimestamps: deletedLabels,
        );
        await settingsRepo.saveWorkspaceSyncState(workspace.id, syncState);
        if (candidateBoard != null &&
            ref.read(activeWorkspaceProvider).asData?.value.id ==
                workspace.id) {
          state = AsyncData(workingBoard);
        }
      }
    }

    if (config.storageMode.usesWebDav &&
        (requireTargets || config.isWebDavConfigured)) {
      final rawRemote = await ref.read(webDavRepositoryProvider).fetchTdf();
      final hasRemoteContent = rawRemote.trim().isNotEmpty;
      if (hasRemoteContent) {
        final remoteBoard = _parseTdf(rawRemote, utcNow, localNow);
        final remoteBaseline = _tryParseBaseline(
          syncState.lastSyncedRemoteTdf,
          utcNow,
          localNow,
        );
        workingBoard = TaskBoardSync.merge(
          primary: hasWorkingBoard ? workingBoard : remoteBoard,
          secondary: remoteBoard,
          baseline: remoteBaseline ?? (hasWorkingBoard ? null : remoteBoard),
          deletedLabelTimestamps: deletedLabels,
          evaluationTime: utcNow,
          localEvaluationTime: localNow,
        );
        hasWorkingBoard = true;
      }
      if (hasRemoteContent || hasWorkingBoard || requireTargets) {
        workingBoard = TaskBoardSync.stampAndNormalize(
          workingBoard,
          evaluationTime: utcNow,
          localEvaluationTime: localNow,
        );
        final serializedFinal = _serializeTdf(workingBoard);
        if (requireTargets ||
            candidateBoard != null ||
            config.storageMode == StorageMode.both ||
            rawRemote.trim() != serializedFinal.trim()) {
          await ref.read(webDavRepositoryProvider).saveTdf(serializedFinal);
        }
        syncState = syncState.copyWith(lastSyncedRemoteTdf: serializedFinal);
        if (config.storageMode.usesLocal &&
            (requireTargets || config.isLocalConfigured)) {
          if (requireTargets ||
              (syncState.lastSyncedLocalTdf ?? '').trim() !=
                  serializedFinal.trim()) {
            await ref
                .read(localFileRepositoryProvider)
                .saveTdf(serializedFinal);
          }
          syncState = syncState.copyWith(lastSyncedLocalTdf: serializedFinal);
        }
      }
    }

    if (!hasWorkingBoard) {
      workingBoard = TaskBoardSync.stampAndNormalize(
        workingBoard,
        evaluationTime: utcNow,
        localEvaluationTime: localNow,
      );
    }

    _pendingDeletedLabelTimestamps.clear();
    syncState = syncState.copyWith(
      deletedLabelTimestamps: const <String, DateTime>{},
    );
    await settingsRepo.saveWorkspaceSyncState(workspace.id, syncState);
    return workingBoard;
  }

  /// Parses [rawBaselineTdf] into a [TaskBoard], or returns `null` when empty or malformed.
  TaskBoard? _tryParseBaseline(
    String? rawBaselineTdf,
    DateTime utcNow,
    DateTime localNow,
  ) {
    if (rawBaselineTdf == null || rawBaselineTdf.trim().isEmpty) {
      return null;
    }
    try {
      return _parseTdf(rawBaselineTdf, utcNow, localNow);
    } on TdfException {
      return null;
    }
  }
}

/// Manages the persisted [WebDavConfig] state for the currently active workspace.
class WebDavConfigNotifier extends AsyncNotifier<WebDavConfig> {
  @override
  Future<WebDavConfig> build() async {
    final activeWorkspace = await ref.watch(activeWorkspaceProvider.future);
    return activeWorkspace.config;
  }

  /// Moves the local `.tdf` file when its resolved path changes and persists [newConfig] atomically.
  Future<void> changeLocalFileLocation(WebDavConfig newConfig) async {
    final current = state.asData?.value ?? await future;
    final localizations = lookupAppLocalizations(
      newConfig.language.resolveLocale(PlatformDispatcher.instance.locale),
    );
    final baseDirectoryPath = ref.read(localStorageDirectoryPathProvider);
    final inMemoryStore = ref.read(_inMemoryLocalStoreProvider);
    final sourceRepo = LocalFileRepository(
      config: current,
      baseDirectoryPath: baseDirectoryPath,
      inMemoryStore: inMemoryStore,
    );
    final targetRepo = LocalFileRepository(
      config: newConfig,
      baseDirectoryPath: baseDirectoryPath,
      inMemoryStore: inMemoryStore,
    );

    final sourcePath = sourceRepo.resolveFilePath();
    final targetPath = targetRepo.resolveFilePath();
    final shouldMove =
        newConfig.storageMode.usesLocal && sourcePath != targetPath;
    if (shouldMove) {
      await sourceRepo.moveTdfFile(targetRepo);
    }

    try {
      await updateConfig(newConfig);
    } on WorkspaceException catch (error) {
      if (shouldMove) {
        await _tryRollbackMove(targetRepo, sourceRepo);
      }
      final message = switch (error.kind) {
        WorkspaceErrorKind.duplicateFilePath =>
          localizations.errorDuplicateWorkspaceFilePath,
        WorkspaceErrorKind.invalidFilePath =>
          localizations.errorInvalidLocalFilePath,
        _ => error.message,
      };
      throw LocalFileException(message, cause: error);
    } on Object {
      if (shouldMove) {
        await _tryRollbackMove(targetRepo, sourceRepo);
      }
      rethrow;
    }
  }

  /// Persists [newConfig] to the active workspace and updates provider state.
  Future<void> updateConfig(WebDavConfig newConfig) async {
    await ref
        .read(activeWorkspaceProvider.notifier)
        .updateActiveConfig(newConfig);
    state = AsyncData(newConfig);
  }

  /// Updates only the display [language] preference and persists it immediately.
  Future<void> updateLanguage(AppLanguage language) async {
    final current = state.asData?.value ?? await future;
    final updated = current.copyWith(language: language);
    await updateConfig(updated);
  }

  /// Updates only the [locationEnabled] preference and persists it immediately.
  Future<void> updateLocationEnabled(bool locationEnabled) async {
    final current = state.asData?.value ?? await future;
    final updated = current.copyWith(locationEnabled: locationEnabled);
    await updateConfig(updated);
  }

  /// Updates only the [manualTimeZoneOffsetMinutes] preference and persists it immediately.
  Future<void> updateManualTimeZoneOffsetMinutes(int offsetMinutes) async {
    final current = state.asData?.value ?? await future;
    final updated = current.copyWith(
      manualTimeZoneOffsetMinutes: offsetMinutes,
    );
    await updateConfig(updated);
  }

  /// Updates only the [storageMode] preference and persists it immediately.
  Future<void> updateStorageMode(StorageMode storageMode) async {
    final current = state.asData?.value ?? await future;
    final updated = current.copyWith(storageMode: storageMode);
    await updateConfig(updated);
  }

  /// Updates only the [themeMode] preference and persists it immediately.
  Future<void> updateThemeMode(AppThemeMode themeMode) async {
    final current = state.asData?.value ?? await future;
    final updated = current.copyWith(themeMode: themeMode);
    await updateConfig(updated);
  }

  /// Updates only the [themePalette] preference and persists it immediately.
  Future<void> updateThemePalette(AppThemePalette themePalette) async {
    final current = state.asData?.value ?? await future;
    final updated = current.copyWith(themePalette: themePalette);
    await updateConfig(updated);
  }

  /// Updates only the [timeZoneMode] preference and persists it immediately.
  Future<void> updateTimeZoneMode(AppTimeZoneMode timeZoneMode) async {
    final current = state.asData?.value ?? await future;
    final updated = current.copyWith(timeZoneMode: timeZoneMode);
    await updateConfig(updated);
  }

  /// Attempts to move the `.tdf` file back from [movedRepo] to [originalRepo] if config persistence fails.
  Future<void> _tryRollbackMove(
    LocalFileRepository movedRepo,
    LocalFileRepository originalRepo,
  ) async {
    try {
      await movedRepo.moveTdfFile(originalRepo);
    } on Object {
      // Preserve primary persistence exception.
    }
  }
}

/// Resolves the active [WebDavConfig] synchronously from [webDavConfigProvider] or [activeWorkspaceProvider].
WebDavConfig _resolveCurrentConfig(Ref ref) {
  final configAsync = ref.watch(webDavConfigProvider);
  if (configAsync.asData?.value case final config?) {
    return config;
  }
  final workspaceAsync = ref.watch(activeWorkspaceProvider);
  return workspaceAsync.asData?.value.config ?? const WebDavConfig();
}
