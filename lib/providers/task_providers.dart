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
import '../models/task_tier.dart';
import '../models/webdav_config.dart';
import '../repositories/settings_repository.dart';
import '../repositories/webdav_repository.dart';
import '../services/markdown_service.dart';

/// Provides the effective [Locale] (`en` or `de`) based on [webDavConfigProvider] and OS locale.
final appLocaleProvider = Provider<Locale>((ref) {
  final configAsync = ref.watch(webDavConfigProvider);
  final language = configAsync.asData?.value.language ?? AppLanguage.system;
  return language.resolveLocale(PlatformDispatcher.instance.locale);
});

/// Injectable clock function for deterministic date handling in unit tests.
final clockProvider = Provider<DateTime Function()>((ref) {
  return DateTime.now;
});

/// Provides the stateless [MarkdownService] parser and serializer.
final markdownServiceProvider = Provider<MarkdownService>((ref) {
  return const MarkdownService();
});

/// Provides the [SettingsRepository] for loading and saving WebDAV and language settings.
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SecureSettingsRepository();
});

/// Provides the current [SyncState] for WebDAV operations.
final syncStateProvider = NotifierProvider<SyncStateNotifier, SyncState>(
  SyncStateNotifier.new,
);

/// Provides the [TaskNotifier] managing the in-memory [TaskBoard] and WebDAV persistence.
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

/// Represents the current synchronization state with the WebDAV server.
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

/// Manages [SyncState] updates during WebDAV load and save operations.
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

/// Manages the in-memory [TaskBoard] and synchronizes mutations to WebDAV.
class TaskNotifier extends AsyncNotifier<TaskBoard> {
  TaskBoard get _currentBoard => state.asData?.value ?? TaskBoard.empty();

  @override
  Future<TaskBoard> build() async {
    final config = await ref.watch(webDavConfigProvider.future);
    if (!config.isConfigured) {
      return TaskBoard.empty();
    }
    return _fetchAndNormalizeBoard();
  }

  /// Adds a new task to [targetTier] (defaulting to `# [3] Planned`), runs the
  /// Auto-Pull Cascade, and persists via WebDAV PUT.
  Future<void> addTask(
    String title, {
    TaskTier targetTier = TaskTier.planned,
    DateTime? currentDate,
    String? id,
  }) async {
    final now = currentDate ?? ref.read(clockProvider)();
    final updated = _currentBoard.addTask(
      title,
      targetTier: targetTier,
      currentDate: now,
      id: id,
    );
    await _commitMutation(updated);
  }

  /// Applies the Auto-Pull Cascade on the current board and persists to WebDAV.
  Future<void> applyAutoPull() async {
    final updated = _currentBoard.applyAutoPull();
    await _commitMutation(updated);
  }

  /// Moves an active task immediately to Tier 4 (`# [4] Blocked`), triggers the
  /// Auto-Pull Cascade, and persists via WebDAV PUT.
  Future<void> blockTask(String taskId, {DateTime? currentDate}) async {
    final now = currentDate ?? ref.read(clockProvider)();
    final updated = _currentBoard.blockTask(taskId, currentDate: now);
    await _commitMutation(updated);
  }

  /// Marks an active task as done in Tier 6 (`# [6] Completed`), prunes expired tasks,
  /// triggers the Auto-Pull Cascade, and persists via WebDAV PUT.
  Future<void> completeTask(String taskId, {DateTime? currentDate}) async {
    final now = currentDate ?? ref.read(clockProvider)();
    final updated = _currentBoard.completeTask(taskId, currentDate: now);
    await _commitMutation(updated);
  }

  /// Permanently deletes a task, runs the Auto-Pull Cascade, and persists via WebDAV PUT.
  Future<void> deleteTask(String taskId, {DateTime? currentDate}) async {
    final now = currentDate ?? ref.read(clockProvider)();
    final updated = _currentBoard.deleteTask(taskId, currentDate: now);
    await _commitMutation(updated);
  }

  /// Downgrades a task one active tier down using anti-ping-pong order and saves via WebDAV PUT.
  Future<void> downgradeTask(String taskId, {DateTime? currentDate}) async {
    final now = currentDate ?? ref.read(clockProvider)();
    final updated = _currentBoard.downgradeTask(taskId, currentDate: now);
    await _commitMutation(updated);
  }

  /// Updates the title of an existing task and saves via WebDAV PUT.
  Future<void> editTaskTitle(String taskId, String newTitle) async {
    final updated = _currentBoard.editTaskTitle(taskId, newTitle);
    await _commitMutation(updated);
  }

  /// Moves a task to [targetTier] and saves via WebDAV PUT.
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

  /// Prunes tasks in Tier 6 (`# [6] Completed`) older than 30 days and persists to WebDAV.
  Future<void> pruneCompletedTasks({DateTime? currentDate}) async {
    final now = currentDate ?? ref.read(clockProvider)();
    final updated = _currentBoard.pruneCompletedTasks(currentDate: now);
    await _commitMutation(updated);
  }

  /// Pushes the current in-memory [board] state to WebDAV via HTTP PUT.
  Future<void> pushToRemote(TaskBoard board) async {
    final config = ref.read(webDavConfigProvider).asData?.value;
    if (config == null || !config.isConfigured) {
      return;
    }

    final webDavRepository = ref.read(webDavRepositoryProvider);
    final serialized = _serializeLocalized(board);

    ref.read(syncStateProvider.notifier).setSyncing();
    try {
      await webDavRepository.saveMarkdown(serialized);
      ref.read(syncStateProvider.notifier).setSuccess(DateTime.now());
    } on Object catch (error) {
      ref.read(syncStateProvider.notifier).setError(error.toString());
    }
  }

  /// Restores a completed task from Tier 6 (`# [6] Completed`) to [targetTier] and saves via WebDAV PUT.
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

  /// Reloads the Markdown file from the WebDAV server via HTTP GET.
  Future<void> syncFromRemote() async {
    final config = await ref.read(webDavConfigProvider.future);
    if (!config.isConfigured) {
      final localizations = lookupAppLocalizations(ref.read(appLocaleProvider));
      ref
          .read(syncStateProvider.notifier)
          .setError(localizations.errorWebDavNotConfigured);
      return;
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetchAndNormalizeBoard);
  }

  /// Tests connection using [config], fetches or initializes the remote file, and updates the board.
  Future<void> testConnectionAndSync(WebDavConfig config) async {
    await ref.read(webDavConfigProvider.notifier).updateConfig(config);
    final webDavRepository = ref.read(webDavRepositoryProvider);
    final markdownService = ref.read(markdownServiceProvider);
    final now = ref.read(clockProvider)();

    ref.read(syncStateProvider.notifier).setSyncing();
    try {
      final rawMarkdown = await webDavRepository.fetchMarkdown();
      final TaskBoard board;
      if (rawMarkdown.trim().isEmpty) {
        final currentBoard = state.asData?.value ?? TaskBoard.empty();
        board = currentBoard
            .pruneCompletedTasks(currentDate: now)
            .applyAutoPull();
      } else {
        final parsed = markdownService.parse(rawMarkdown);
        board = parsed.pruneCompletedTasks(currentDate: now).applyAutoPull();
      }
      await webDavRepository.saveMarkdown(_serializeLocalized(board));
      state = AsyncData(board);
      ref.read(syncStateProvider.notifier).setSuccess(DateTime.now());
    } on Object catch (error) {
      ref.read(syncStateProvider.notifier).setError(error.toString());
      rethrow;
    }
  }

  /// Updates the in-memory board state and pushes the serialized Markdown to WebDAV.
  Future<void> _commitMutation(TaskBoard updatedBoard) async {
    state = AsyncData(updatedBoard);
    await pushToRemote(updatedBoard);
  }

  /// Fetches the remote Markdown file, normalizes the board, and writes back if changed.
  Future<TaskBoard> _fetchAndNormalizeBoard() async {
    final webDavRepository = ref.read(webDavRepositoryProvider);
    final markdownService = ref.read(markdownServiceProvider);
    final now = ref.read(clockProvider)();

    ref.read(syncStateProvider.notifier).setSyncing();
    try {
      final rawMarkdown = await webDavRepository.fetchMarkdown();
      final parsedBoard = markdownService.parse(rawMarkdown);
      final normalizedBoard = parsedBoard
          .pruneCompletedTasks(currentDate: now)
          .applyAutoPull();

      final normalizedMarkdown = _serializeLocalized(normalizedBoard);
      if (rawMarkdown.trim().isNotEmpty &&
          rawMarkdown.trim() != normalizedMarkdown.trim()) {
        await webDavRepository.saveMarkdown(normalizedMarkdown);
      }

      ref.read(syncStateProvider.notifier).setSuccess(DateTime.now());
      return normalizedBoard;
    } on Object catch (error) {
      ref.read(syncStateProvider.notifier).setError(error.toString());
      rethrow;
    }
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
}

/// Manages the persisted [WebDavConfig] state, including language selection.
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
}
