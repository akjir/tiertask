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
import '../l10n/tier_localization_extension.dart';
import '../models/task_board.dart';
import '../models/task_item.dart';
import '../models/task_tier.dart';
import '../models/webdav_config.dart';
import '../repositories/local_file_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/webdav_repository.dart';
import '../services/markdown_service.dart';

/// Provides the effective [Locale] (`en` or `de`) based on [webDavConfigProvider] and OS locale.
final appLocaleProvider = Provider<Locale>((ref) {
  final configAsync = ref.watch(webDavConfigProvider);
  final language = configAsync.asData?.value.language ?? AppLanguage.system;
  return language.resolveLocale(PlatformDispatcher.instance.locale);
});

/// Provides the selected [AppThemeMode] (`system`, `light`, or `dark`) from [webDavConfigProvider].
final appThemeModeProvider = Provider<AppThemeMode>((ref) {
  final configAsync = ref.watch(webDavConfigProvider);
  return configAsync.asData?.value.themeMode ?? AppThemeMode.system;
});

/// Injectable clock function for deterministic date handling in unit tests.
final clockProvider = Provider<DateTime Function()>((ref) {
  return DateTime.now;
});

/// Provides a [LocalFileRepository] configured with the current [WebDavConfig].
final localFileRepositoryProvider = Provider<LocalFileRepository>((ref) {
  final configAsync = ref.watch(webDavConfigProvider);
  final config = configAsync.asData?.value ?? const WebDavConfig();
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

/// Provides the stateless [MarkdownService] parser and serializer.
final markdownServiceProvider = Provider<MarkdownService>((ref) {
  return const MarkdownService();
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

/// Provides the persisted [WebDavConfig] state.
final webDavConfigProvider =
    AsyncNotifierProvider<WebDavConfigNotifier, WebDavConfig>(
      WebDavConfigNotifier.new,
    );

/// Provides a [WebDavRepository] configured with the current [WebDavConfig].
final webDavRepositoryProvider = Provider<WebDavRepository>((ref) {
  final configAsync = ref.watch(webDavConfigProvider);
  final config = configAsync.asData?.value ?? const WebDavConfig();
  return WebDavRepository(config: config);
});

/// Provides an isolated in-memory file map for hermetic widget tests.
final _inMemoryLocalStoreProvider = Provider<Map<String, String>>((ref) {
  return <String, String>{};
});

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
  SyncState build() => const SyncState();

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
    final config = await ref.watch(webDavConfigProvider.future);
    if (!config.hasActiveStorage) {
      return TaskBoard.empty();
    }
    return _fetchAndNormalizeBoard(config);
  }

  /// Adds a new task to [targetTier] (defaulting to `# [3] Planned`), runs the
  /// Auto-Pull Cascade, and persists to the active storage backend.
  Future<void> addTask(
    String title, {
    TaskTier targetTier = TaskTier.planned,
    bool isPriority = false,
    List<SubtaskItem> subtasks = const [],
    DateTime? currentDate,
    String? id,
  }) async {
    final now = currentDate ?? ref.read(clockProvider)();
    final updated = _currentBoard.addTask(
      title,
      targetTier: targetTier,
      isPriority: isPriority,
      subtasks: subtasks,
      currentDate: now,
      id: id,
    );
    await _commitMutation(updated);
  }

  /// Applies the Auto-Pull Cascade on the current board and persists to storage.
  Future<void> applyAutoPull() async {
    final updated = _currentBoard.applyAutoPull();
    await _commitMutation(updated);
  }

  /// Moves an active task immediately to Tier 4 (`# [4] Blocked`), triggers the
  /// Auto-Pull Cascade, and persists to storage.
  Future<void> blockTask(String taskId, {DateTime? currentDate}) async {
    final now = currentDate ?? ref.read(clockProvider)();
    final updated = _currentBoard.blockTask(taskId, currentDate: now);
    await _commitMutation(updated);
  }

  /// Marks an active task as done in Tier 6 (`# [6] Completed`), prunes expired tasks,
  /// triggers the Auto-Pull Cascade, and persists to storage.
  Future<void> completeTask(String taskId, {DateTime? currentDate}) async {
    final now = currentDate ?? ref.read(clockProvider)();
    final updated = _currentBoard.completeTask(taskId, currentDate: now);
    await _commitMutation(updated);
  }

  /// Permanently deletes a task, runs the Auto-Pull Cascade, and persists to storage.
  Future<void> deleteTask(String taskId, {DateTime? currentDate}) async {
    final now = currentDate ?? ref.read(clockProvider)();
    final updated = _currentBoard.deleteTask(taskId, currentDate: now);
    await _commitMutation(updated);
  }

  /// Downgrades a task one active tier down using anti-ping-pong order and saves to storage.
  Future<void> downgradeTask(String taskId, {DateTime? currentDate}) async {
    final now = currentDate ?? ref.read(clockProvider)();
    final updated = _currentBoard.downgradeTask(taskId, currentDate: now);
    await _commitMutation(updated);
  }

  /// Updates the title of an existing task and saves to storage.
  Future<void> editTaskTitle(String taskId, String newTitle) async {
    final updated = _currentBoard.editTaskTitle(taskId, newTitle);
    await _commitMutation(updated);
  }

  /// Moves a task to [targetTier] and saves to storage.
  Future<void> moveTask(
    String taskId,
    TaskTier targetTier, {
    DateTime? currentDate,
  }) async {
    final now = currentDate ?? ref.read(clockProvider)();
    final updated = _currentBoard.moveTask(
      taskId,
      targetTier,
      currentDate: now,
    );
    await _commitMutation(updated);
  }

  /// Prunes tasks in Tier 6 (`# [6] Completed`) older than 30 days and persists to storage.
  Future<void> pruneCompletedTasks({DateTime? currentDate}) async {
    final now = currentDate ?? ref.read(clockProvider)();
    final updated = _currentBoard.pruneCompletedTasks(currentDate: now);
    await _commitMutation(updated);
  }

  /// Persists the current in-memory [board] state to the configured local and/or WebDAV storage.
  Future<void> pushToRemote(TaskBoard board) async {
    final config = ref.read(webDavConfigProvider).asData?.value;
    if (config == null || !config.hasActiveStorage) {
      return;
    }

    final serialized = _serializeLocalized(board);
    ref.read(syncStateProvider.notifier).setSyncing();
    try {
      await _writeBoardToConfiguredTargets(config, serialized);
      ref.read(syncStateProvider.notifier).setSuccess(DateTime.now());
    } on Object catch (error) {
      ref.read(syncStateProvider.notifier).setError(error.toString());
    }
  }

  /// Restores a completed task from Tier 6 (`# [6] Completed`) to [targetTier] and saves to storage.
  Future<void> restoreTask(
    String taskId,
    TaskTier targetTier, {
    DateTime? currentDate,
  }) async {
    final now = currentDate ?? ref.read(clockProvider)();
    final updated = _currentBoard.restoreTask(
      taskId,
      targetTier,
      currentDate: now,
    );
    await _commitMutation(updated);
  }

  /// Reloads the Markdown file from the configured local or WebDAV storage backend.
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

  /// Tests storage access using [config], fetches or initializes the Markdown file, and updates the board.
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
      final rawMarkdown = await _loadRawMarkdownForSync(config);
      final board = _resolveBoardFromMarkdown(rawMarkdown, now);
      final serialized = _serializeLocalized(board);
      await _writeBoardToRequiredTargets(config, serialized);
      state = AsyncData(board);
      ref.read(syncStateProvider.notifier).setSuccess(DateTime.now());
    } on Object catch (error) {
      ref.read(syncStateProvider.notifier).setError(error.toString());
      rethrow;
    }
  }

  /// Updates the in-memory board state and persists the serialized Markdown.
  Future<void> _commitMutation(TaskBoard updatedBoard) async {
    state = AsyncData(updatedBoard);
    await pushToRemote(updatedBoard);
  }

  /// Loads the Markdown file from the active backend, normalizes the board, and writes back if changed.
  Future<TaskBoard> _fetchAndNormalizeBoard(WebDavConfig config) async {
    final markdownService = ref.read(markdownServiceProvider);
    final now = ref.read(clockProvider)();

    ref.read(syncStateProvider.notifier).setSyncing();
    try {
      final rawMarkdown = await _loadRawMarkdownForSync(config);
      final parsedBoard = markdownService.parse(rawMarkdown);
      final normalizedBoard = parsedBoard
          .pruneCompletedTasks(currentDate: now)
          .applyAutoPull();
      final normalizedMarkdown = _serializeLocalized(normalizedBoard);

      await _persistNormalizedMarkdown(config, rawMarkdown, normalizedMarkdown);
      ref.read(syncStateProvider.notifier).setSuccess(DateTime.now());
      return normalizedBoard;
    } on Object catch (error) {
      ref.read(syncStateProvider.notifier).setError(error.toString());
      rethrow;
    }
  }

  /// Loads raw Markdown text according to [config.storageMode].
  Future<String> _loadRawMarkdownForSync(WebDavConfig config) async {
    return switch (config.storageMode) {
      StorageMode.local => ref.read(localFileRepositoryProvider).loadMarkdown(),
      StorageMode.webdav => ref.read(webDavRepositoryProvider).fetchMarkdown(),
      StorageMode.both => _loadRawMarkdownInBothMode(config),
    };
  }

  /// Loads raw Markdown in [StorageMode.both], preferring remote content and falling back to local content.
  Future<String> _loadRawMarkdownInBothMode(WebDavConfig config) async {
    if (config.isWebDavConfigured) {
      final remote = await ref.read(webDavRepositoryProvider).fetchMarkdown();
      if (remote.trim().isNotEmpty) {
        return remote;
      }
    }
    if (config.isLocalConfigured) {
      return ref.read(localFileRepositoryProvider).loadMarkdown();
    }
    return '';
  }

  /// Writes back [normalizedMarkdown] when normalization modified [rawMarkdown] or when syncing both backends.
  Future<void> _persistNormalizedMarkdown(
    WebDavConfig config,
    String rawMarkdown,
    String normalizedMarkdown,
  ) async {
    final hasContent = rawMarkdown.trim().isNotEmpty;
    if (!hasContent) {
      return;
    }
    final isChanged = rawMarkdown.trim() != normalizedMarkdown.trim();
    if (config.storageMode == StorageMode.both || isChanged) {
      await _writeBoardToConfiguredTargets(config, normalizedMarkdown);
    }
  }

  /// Parses [rawMarkdown] or normalizes the existing board when [rawMarkdown] is empty.
  TaskBoard _resolveBoardFromMarkdown(String rawMarkdown, DateTime now) {
    if (rawMarkdown.trim().isEmpty) {
      final currentBoard = state.asData?.value ?? TaskBoard.empty();
      return currentBoard.pruneCompletedTasks(currentDate: now).applyAutoPull();
    }
    final parsed = ref.read(markdownServiceProvider).parse(rawMarkdown);
    return parsed.pruneCompletedTasks(currentDate: now).applyAutoPull();
  }

  /// Serializes [board] using the active locale's tier labels.
  String _serializeLocalized(TaskBoard board) {
    final markdownService = ref.read(markdownServiceProvider);
    final locale = ref.read(appLocaleProvider);
    final localizations = lookupAppLocalizations(locale);
    return markdownService.serialize(
      board,
      tierLabelBuilder: localizations.tierName,
    );
  }

  /// Writes [serialized] to all configured targets enabled by [config.storageMode].
  Future<void> _writeBoardToConfiguredTargets(
    WebDavConfig config,
    String serialized,
  ) async {
    if (config.storageMode.usesLocal && config.isLocalConfigured) {
      await ref.read(localFileRepositoryProvider).saveMarkdown(serialized);
    }
    if (config.storageMode.usesWebDav && config.isWebDavConfigured) {
      await ref.read(webDavRepositoryProvider).saveMarkdown(serialized);
    }
  }

  /// Writes [serialized] to all targets required by [config.storageMode] during an explicit sync test.
  Future<void> _writeBoardToRequiredTargets(
    WebDavConfig config,
    String serialized,
  ) async {
    if (config.storageMode.usesLocal) {
      await ref.read(localFileRepositoryProvider).saveMarkdown(serialized);
    }
    if (config.storageMode.usesWebDav) {
      await ref.read(webDavRepositoryProvider).saveMarkdown(serialized);
    }
  }
}

/// Manages the persisted [WebDavConfig] state, including language, theme, and storage mode selection.
class WebDavConfigNotifier extends AsyncNotifier<WebDavConfig> {
  @override
  Future<WebDavConfig> build() async {
    final repository = ref.watch(settingsRepositoryProvider);
    return repository.loadConfig();
  }

  /// Persists [newConfig] and updates provider state.
  Future<void> updateConfig(WebDavConfig newConfig) async {
    final repository = ref.read(settingsRepositoryProvider);
    await repository.saveConfig(newConfig);
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
