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
import '../models/task_board.dart';
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

/// Provides the active [AppThemeSet] (`light` and `dark` [AppTheme] pair) replaceable at runtime.
final appThemeProvider = NotifierProvider<AppThemeNotifier, AppThemeSet>(
  AppThemeNotifier.new,
);

/// Injectable clock function for deterministic date handling in unit tests.
final clockProvider = Provider<DateTime Function()>((ref) {
  return DateTime.now;
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
  AppThemeSet build() => AppThemeSet.standard;

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
  TaskBoard get _currentBoard => state.asData?.value ?? TaskBoard.empty();

  @override
  Future<TaskBoard> build() async {
    state = const AsyncLoading();
    final config = await ref.watch(webDavConfigProvider.future);
    if (!config.hasActiveStorage) {
      return TaskBoard.empty();
    }
    return _fetchAndNormalizeBoard(config);
  }

  /// Adds a new TDF `label` block with [name] and optional `#RRGGBB` [color] and persists to storage.
  Future<void> addLabel(
    String name, {
    String? color,
    String? id,
    String? note,
  }) async {
    final updated = _currentBoard.addLabel(
      name,
      color: color,
      id: id,
      note: note,
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
    List<String> blockedByTaskIds = const [],
    List<TaskCondition> conditions = const [],
    DateTime? currentDate,
    String? id,
  }) async {
    final now = currentDate ?? ref.read(clockProvider)();
    final updated = _currentBoard.addTask(
      title,
      note: note,
      targetTier: targetTier,
      isPriority: isPriority,
      subtasksAutoFinish: subtasksAutoFinish,
      subtasks: subtasks,
      labelIds: labelIds,
      suspendedAt: suspendedAt,
      blockedByTaskIds: blockedByTaskIds,
      conditions: conditions,
      currentDate: now,
      id: id,
    );
    await _commitMutation(updated);
  }

  /// Marks an active task as done in Tier 6 ([TaskTier.completed]), prunes expired tasks,
  /// triggers the Auto-Pull Cascade, and persists to storage.
  Future<void> completeTask(String taskId, {DateTime? currentDate}) async {
    final now = currentDate ?? ref.read(clockProvider)();
    final updated = _currentBoard.completeTask(taskId, currentDate: now);
    await _commitMutation(updated);
  }

  /// Deletes the label with [labelId], strips its reference from all tasks, and persists to storage.
  Future<void> deleteLabel(String labelId) async {
    final updated = _currentBoard.deleteLabel(labelId);
    await _commitMutation(updated);
  }

  /// Downgrades an active task per `TDF_SPEC.md` Section 6.3 and persists to storage.
  Future<void> downgradeTask(String taskId, {DateTime? currentDate}) async {
    final now = currentDate ?? ref.read(clockProvider)();
    final updated = _currentBoard.downgradeTask(taskId, currentDate: now);
    await _commitMutation(updated);
  }

  /// Persists the current in-memory [board] state to the configured local and/or WebDAV `.tdf` storage.
  Future<void> pushToRemote(TaskBoard board) async {
    final WebDavConfig config =
        ref.read(webDavConfigProvider).asData?.value ??
        await ref.read(webDavConfigProvider.future);
    if (!config.hasActiveStorage) {
      return;
    }

    final serialized = _serializeTdf(board);
    ref.read(syncStateProvider.notifier).setSyncing();
    try {
      await _writeBoardToConfiguredTargets(config, serialized);
      ref.read(syncStateProvider.notifier).setSuccess(DateTime.now());
    } on Object catch (error) {
      ref.read(syncStateProvider.notifier).setError(error.toString());
    }
  }

  /// Updates the display [name] of the label with [labelId] and persists to storage.
  Future<void> renameLabel(String labelId, String name) async {
    final updated = _currentBoard.renameLabel(labelId, name);
    await _commitMutation(updated);
  }

  /// Restores a completed task to [targetTier] (defaulting to [TaskTier.planned]) per
  /// `TDF_SPEC.md` Section 6.5 and persists to storage.
  Future<void> restoreTask(
    String taskId, {
    TaskTier targetTier = TaskTier.planned,
    DateTime? currentDate,
  }) async {
    final now = currentDate ?? ref.read(clockProvider)();
    final updated = _currentBoard.restoreTask(
      taskId,
      targetTier: targetTier,
      currentDate: now,
    );
    await _commitMutation(updated);
  }

  /// Reloads the `.tdf` file from the configured local or WebDAV storage backend.
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

    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetchAndNormalizeBoard(config));
  }

  /// Tests storage access using [config], fetches or initializes the `.tdf` file, and updates the board.
  Future<void> testConnectionAndSync(WebDavConfig config) async {
    final localizations = lookupAppLocalizations(ref.read(appLocaleProvider));
    if (!config.storageMode.usesWebDav || !config.isWebDavConfigured) {
      final exception = WebDavException(localizations.errorWebDavNotConfigured);
      ref.read(syncStateProvider.notifier).setError(exception.toString());
      throw exception;
    }

    await ref.read(webDavConfigProvider.notifier).updateConfig(config);
    final now = ref.read(clockProvider)();

    ref.read(syncStateProvider.notifier).setSyncing();
    try {
      final rawTdf = await _loadRawTdfForSync(config);
      final board = _resolveBoardFromTdf(
        rawTdf,
        now,
        fallbackBoard: state.asData?.value ?? TaskBoard.empty(),
      );
      final serialized = _serializeTdf(board);
      await _writeBoardToRequiredTargets(config, serialized);
      state = AsyncData(board);
      ref.read(syncStateProvider.notifier).setSuccess(DateTime.now());
    } on Object catch (error) {
      ref.read(syncStateProvider.notifier).setError(error.toString());
      rethrow;
    }
  }

  /// Toggles the subtask step at [stepIndex] on [taskId] and persists to storage.
  Future<void> toggleSubtask(
    String taskId,
    int stepIndex, {
    DateTime? currentDate,
  }) async {
    final now = currentDate ?? ref.read(clockProvider)();
    final updated = _currentBoard.toggleSubtask(
      taskId,
      stepIndex,
      currentDate: now,
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
    List<String>? blockedByTaskIds,
    List<TaskCondition>? conditions,
    DateTime? currentDate,
  }) async {
    final now = currentDate ?? ref.read(clockProvider)();
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
      blockedByTaskIds: blockedByTaskIds,
      conditions: conditions,
      currentDate: now,
    );
    await _commitMutation(updated);
  }

  /// Updates the in-memory board state and persists the serialized `.tdf` document.
  Future<void> _commitMutation(TaskBoard updatedBoard) async {
    state = AsyncData(updatedBoard);
    await pushToRemote(updatedBoard);
  }

  /// Loads the `.tdf` file from the active backend, normalizes the board, and writes back if changed.
  Future<TaskBoard> _fetchAndNormalizeBoard(WebDavConfig config) async {
    final now = ref.read(clockProvider)();

    ref.read(syncStateProvider.notifier).setSyncing();
    try {
      final rawTdf = await _loadRawTdfForSync(config);
      final normalizedBoard = _resolveBoardFromTdf(
        rawTdf,
        now,
        fallbackBoard: TaskBoard.empty(),
      );
      final normalizedTdf = _serializeTdf(normalizedBoard);

      await _persistNormalizedTdf(config, rawTdf, normalizedTdf);
      ref.read(syncStateProvider.notifier).setSuccess(DateTime.now());
      return normalizedBoard;
    } on Object catch (error) {
      ref.read(syncStateProvider.notifier).setError(error.toString());
      rethrow;
    }
  }

  /// Loads raw `.tdf` text according to [config.storageMode].
  Future<String> _loadRawTdfForSync(WebDavConfig config) async {
    return switch (config.storageMode) {
      StorageMode.local => ref.read(localFileRepositoryProvider).loadTdf(),
      StorageMode.webdav => ref.read(webDavRepositoryProvider).fetchTdf(),
      StorageMode.both => _loadRawTdfInBothMode(config),
    };
  }

  /// Loads raw `.tdf` in [StorageMode.both], preferring remote content and falling back to local content.
  Future<String> _loadRawTdfInBothMode(WebDavConfig config) async {
    if (config.isWebDavConfigured) {
      final remote = await ref.read(webDavRepositoryProvider).fetchTdf();
      if (remote.trim().isNotEmpty) {
        return remote;
      }
    }
    if (config.isLocalConfigured) {
      return ref.read(localFileRepositoryProvider).loadTdf();
    }
    return '';
  }

  /// Writes back [normalizedTdf] when normalization modified [rawTdf] or when syncing both backends.
  Future<void> _persistNormalizedTdf(
    WebDavConfig config,
    String rawTdf,
    String normalizedTdf,
  ) async {
    final hasContent = rawTdf.trim().isNotEmpty;
    if (!hasContent) {
      return;
    }
    final isChanged = rawTdf.trim() != normalizedTdf.trim();
    if (config.storageMode == StorageMode.both || isChanged) {
      await _writeBoardToConfiguredTargets(config, normalizedTdf);
    }
  }

  /// Parses [rawTdf] or normalizes [fallbackBoard] when [rawTdf] is empty.
  TaskBoard _resolveBoardFromTdf(
    String rawTdf,
    DateTime now, {
    required TaskBoard fallbackBoard,
  }) {
    if (rawTdf.trim().isEmpty) {
      return fallbackBoard
          .pruneCompletedTasks(currentDate: now)
          .applyAutoPull(currentDate: now);
    }
    final parsed = ref
        .read(tdfServiceProvider)
        .parse(rawTdf, evaluationTime: now);
    return parsed
        .pruneCompletedTasks(currentDate: now)
        .applyAutoPull(currentDate: now);
  }

  /// Serializes [board] into canonical `.tdf` text.
  String _serializeTdf(TaskBoard board) {
    return ref.read(tdfServiceProvider).serialize(board);
  }

  /// Writes [serialized] to all configured targets enabled by [config.storageMode].
  Future<void> _writeBoardToConfiguredTargets(
    WebDavConfig config,
    String serialized,
  ) async {
    if (config.storageMode.usesLocal && config.isLocalConfigured) {
      await ref.read(localFileRepositoryProvider).saveTdf(serialized);
    }
    if (config.storageMode.usesWebDav && config.isWebDavConfigured) {
      await ref.read(webDavRepositoryProvider).saveTdf(serialized);
    }
  }

  /// Writes [serialized] to all targets required by [config.storageMode] during an explicit sync test.
  Future<void> _writeBoardToRequiredTargets(
    WebDavConfig config,
    String serialized,
  ) async {
    if (config.storageMode.usesLocal) {
      await ref.read(localFileRepositoryProvider).saveTdf(serialized);
    }
    if (config.storageMode.usesWebDav) {
      await ref.read(webDavRepositoryProvider).saveTdf(serialized);
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

  /// Updates only the [showOpenTaskCount] preference and persists it immediately.
  Future<void> updateShowOpenTaskCount(bool showOpenTaskCount) async {
    final current = state.asData?.value ?? await future;
    final updated = current.copyWith(showOpenTaskCount: showOpenTaskCount);
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
