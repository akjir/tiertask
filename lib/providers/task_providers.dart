import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task_board.dart';
import '../models/task_tier.dart';
import '../models/webdav_config.dart';
import '../repositories/settings_repository.dart';
import '../repositories/webdav_repository.dart';
import '../services/markdown_service.dart';

/// Provides the stateless [MarkdownService] parser and serializer.
final markdownServiceProvider = Provider<MarkdownService>((ref) {
  return const MarkdownService();
});

/// Provides the [SettingsRepository] for loading/saving WebDAV credentials.
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SecureSettingsRepository();
});

/// Injectable clock function for deterministic date handling in unit tests.
final clockProvider = Provider<DateTime Function()>((ref) {
  return DateTime.now;
});

/// Represents the current synchronization state with the Nextcloud WebDAV server.
class SyncState {
  const SyncState({
    this.isSyncing = false,
    this.lastSyncedAt,
    this.errorMessage,
  });

  final bool isSyncing;
  final DateTime? lastSyncedAt;
  final String? errorMessage;

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

class SyncStateNotifier extends Notifier<SyncState> {
  @override
  SyncState build() => const SyncState();

  void setSyncing() {
    state = state.copyWith(isSyncing: true, clearError: true);
  }

  void setSuccess(DateTime timestamp) {
    state = SyncState(
      isSyncing: false,
      lastSyncedAt: timestamp,
      errorMessage: null,
    );
  }

  void setError(String message) {
    state = state.copyWith(isSyncing: false, errorMessage: message);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

final syncStateProvider = NotifierProvider<SyncStateNotifier, SyncState>(
  SyncStateNotifier.new,
);

/// Manages the persisted [WebDavConfig] state.
class WebDavConfigNotifier extends AsyncNotifier<WebDavConfig> {
  @override
  Future<WebDavConfig> build() async {
    final repo = ref.watch(settingsRepositoryProvider);
    return repo.loadConfig();
  }

  Future<void> updateConfig(WebDavConfig newConfig) async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.saveConfig(newConfig);
    state = AsyncData(newConfig);
  }
}

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

/// Domain & State Controller (`TaskNotifier`) managing the in-memory [TaskBoard]
/// and synchronizing mutations to Nextcloud via WebDAV HTTP PUT.
class TaskNotifier extends AsyncNotifier<TaskBoard> {
  @override
  Future<TaskBoard> build() async {
    final config = await ref.watch(webDavConfigProvider.future);
    if (!config.isConfigured) {
      return TaskBoard.empty();
    }
    return _fetchAndNormalizeBoard();
  }

  Future<TaskBoard> _fetchAndNormalizeBoard() async {
    final webDavRepo = ref.read(webDavRepositoryProvider);
    final markdownService = ref.read(markdownServiceProvider);
    final now = ref.read(clockProvider)();

    ref.read(syncStateProvider.notifier).setSyncing();
    try {
      final rawMarkdown = await webDavRepo.fetchMarkdown();
      final parsedBoard = markdownService.parse(rawMarkdown);
      final normalizedBoard = parsedBoard
          .pruneCompletedTasks(currentDate: now)
          .applyAutoPull();

      final normalizedMarkdown = markdownService.serialize(normalizedBoard);
      if (rawMarkdown.trim().isNotEmpty &&
          rawMarkdown.trim() != normalizedMarkdown.trim()) {
        await webDavRepo.saveMarkdown(normalizedMarkdown);
      }

      ref.read(syncStateProvider.notifier).setSuccess(DateTime.now());
      return normalizedBoard;
    } catch (e) {
      ref.read(syncStateProvider.notifier).setError(e.toString());
      rethrow;
    }
  }

  /// Reloads the Markdown file from Nextcloud via WebDAV GET.
  Future<void> syncFromRemote() async {
    final config = await ref.read(webDavConfigProvider.future);
    if (!config.isConfigured) {
      ref
          .read(syncStateProvider.notifier)
          .setError(
            'Bitte zuerst Nextcloud WebDAV in den Einstellungen konfigurieren.',
          );
      return;
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetchAndNormalizeBoard);
  }

  /// Pushes the current in-memory board state to Nextcloud via WebDAV PUT.
  Future<void> pushToRemote(TaskBoard board) async {
    final config = ref.read(webDavConfigProvider).asData?.value;
    if (config == null || !config.isConfigured) {
      return;
    }

    final webDavRepo = ref.read(webDavRepositoryProvider);
    final markdownService = ref.read(markdownServiceProvider);
    final serialized = markdownService.serialize(board);

    ref.read(syncStateProvider.notifier).setSyncing();
    try {
      await webDavRepo.saveMarkdown(serialized);
      ref.read(syncStateProvider.notifier).setSuccess(DateTime.now());
    } catch (e) {
      ref.read(syncStateProvider.notifier).setError(e.toString());
    }
  }

  /// Tests connection using [config]: fetches the remote file (or creates it if empty)
  /// and updates the board state.
  Future<void> testConnectionAndSync(WebDavConfig config) async {
    await ref.read(webDavConfigProvider.notifier).updateConfig(config);
    final webDavRepo = ref.read(webDavRepositoryProvider);
    final markdownService = ref.read(markdownServiceProvider);
    final now = ref.read(clockProvider)();

    ref.read(syncStateProvider.notifier).setSyncing();
    try {
      final rawMarkdown = await webDavRepo.fetchMarkdown();
      TaskBoard board;
      if (rawMarkdown.trim().isEmpty) {
        // If remote file does not exist yet or is empty, upload current board
        final currentBoard = state.asData?.value ?? TaskBoard.empty();
        board = currentBoard
            .pruneCompletedTasks(currentDate: now)
            .applyAutoPull();
        await webDavRepo.saveMarkdown(markdownService.serialize(board));
      } else {
        final parsed = markdownService.parse(rawMarkdown);
        board = parsed.pruneCompletedTasks(currentDate: now).applyAutoPull();
        await webDavRepo.saveMarkdown(markdownService.serialize(board));
      }
      state = AsyncData(board);
      ref.read(syncStateProvider.notifier).setSuccess(DateTime.now());
    } catch (e) {
      ref.read(syncStateProvider.notifier).setError(e.toString());
      rethrow;
    }
  }

  TaskBoard get _currentBoard => state.asData?.value ?? TaskBoard.empty();

  Future<void> _commitMutation(TaskBoard updatedBoard) async {
    state = AsyncData(updatedBoard);
    await pushToRemote(updatedBoard);
  }

  /// Applies the Auto-Pull Cascade on the current board and persists to WebDAV.
  Future<void> applyAutoPull() async {
    final updated = _currentBoard.applyAutoPull();
    await _commitMutation(updated);
  }

  /// Prunes tasks in `# Erledigt` older than 30 days and persists to WebDAV.
  Future<void> pruneCompletedTasks({DateTime? currentDate}) async {
    final now = currentDate ?? ref.read(clockProvider)();
    final updated = _currentBoard.pruneCompletedTasks(currentDate: now);
    await _commitMutation(updated);
  }

  /// Adds a new task to [targetTier] (defaults to `# Geplant`), cascades upward
  /// if `# Bereit` or `# Fokus` have capacity, and persists via WebDAV PUT.
  Future<void> addTask(
    String title, {
    TaskTier targetTier = TaskTier.geplant,
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

  /// Marks an active task as done, stamps it with `YYYY-MM-DD` at the top of `# Erledigt`,
  /// prunes 30+ day old completed tasks, triggers Auto-Pull Cascade, and saves via WebDAV PUT.
  Future<void> completeTask(String taskId, {DateTime? currentDate}) async {
    final now = currentDate ?? ref.read(clockProvider)();
    final updated = _currentBoard.completeTask(taskId, currentDate: now);
    await _commitMutation(updated);
  }

  /// Restores a completed task from `# Erledigt` to [targetTier], strips `[x]` and date,
  /// triggers Auto-Pull Cascade, and saves via WebDAV PUT.
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

  /// Downgrades a task (`# Fokus` -> `# Bereit` or `# Bereit` -> `# Geplant`)
  /// using anti-ping-pong pull order and saves via WebDAV PUT.
  Future<void> downgradeTask(String taskId, {DateTime? currentDate}) async {
    final now = currentDate ?? ref.read(clockProvider)();
    final updated = _currentBoard.downgradeTask(taskId, currentDate: now);
    await _commitMutation(updated);
  }

  /// Quick-Block Action: Moves an active task immediately to `# Blockiert`,
  /// triggers Auto-Pull Cascade to refill the vacated slot, and saves via WebDAV PUT.
  Future<void> blockTask(String taskId, {DateTime? currentDate}) async {
    final now = currentDate ?? ref.read(clockProvider)();
    final updated = _currentBoard.blockTask(taskId, currentDate: now);
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

  /// Edits the title of an existing task and saves via WebDAV PUT.
  Future<void> editTaskTitle(String taskId, String newTitle) async {
    final updated = _currentBoard.editTaskTitle(taskId, newTitle);
    await _commitMutation(updated);
  }

  /// Permanently deletes a task, runs Auto-Pull Cascade, and saves via WebDAV PUT.
  Future<void> deleteTask(String taskId, {DateTime? currentDate}) async {
    final now = currentDate ?? ref.read(clockProvider)();
    final updated = _currentBoard.deleteTask(taskId, currentDate: now);
    await _commitMutation(updated);
  }
}

final taskNotifierProvider = AsyncNotifierProvider<TaskNotifier, TaskBoard>(
  TaskNotifier.new,
);
