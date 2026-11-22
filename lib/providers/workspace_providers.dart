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

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_build_profile.dart';
import '../models/app_workspace.dart';
import '../models/webdav_config.dart';
import '../repositories/settings_repository.dart';
import '../services/app_logger.dart';

/// Provides the single currently loaded [AppWorkspace] in memory.
final activeWorkspaceProvider =
    AsyncNotifierProvider<ActiveWorkspaceNotifier, AppWorkspace>(
      ActiveWorkspaceNotifier.new,
      retry: disableProviderRetry,
    );

/// Provides the active [AppBuildProfile] (`release` or `dev`), overridable in tests.
final appBuildProfileProvider = Provider<AppBuildProfile>((ref) {
  return AppBuildProfile.current;
});

/// Optional directory override for host-local `settings.json` persistence, primarily for hermetic tests.
final settingsDirectoryPathProvider = Provider<String?>((ref) => null);

/// Provides the [SettingsRepository] for loading and saving application settings.
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final buildProfile = ref.watch(appBuildProfileProvider);
  final settingsDirectoryPath = ref.watch(settingsDirectoryPathProvider);
  return SecureSettingsRepository(
    buildProfile: buildProfile,
    settingsDirectoryPath: settingsDirectoryPath,
  );
});

/// Provides lightweight [WorkspaceSummary] entries for all persisted workspaces.
final workspaceSummariesProvider = FutureProvider<List<WorkspaceSummary>>((
  ref,
) {
  ref.watch(_workspaceListRevisionProvider);
  final repository = ref.watch(settingsRepositoryProvider);
  return repository.loadWorkspaceSummaries();
});

/// Provides the [WorkspaceUnloadCoordinator] for flushing state before unloading a workspace.
final workspaceUnloadCoordinatorProvider = Provider<WorkspaceUnloadCoordinator>(
  (ref) {
    return WorkspaceUnloadCoordinator();
  },
);

/// Internal revision counter incremented whenever the persisted workspace list changes.
final _workspaceListRevisionProvider =
    NotifierProvider<_WorkspaceListRevisionNotifier, int>(
      _WorkspaceListRevisionNotifier.new,
    );

/// Manages the single active [AppWorkspace] in memory and orchestrates workspace unload and load transitions.
class ActiveWorkspaceNotifier extends AsyncNotifier<AppWorkspace> {
  Future<void> _lifecycleQueue = Future<void>.value();
  Future<void> _repositoryQueue = Future<void>.value();

  @override
  Future<AppWorkspace> build() {
    _lifecycleQueue = Future<void>.value();
    _repositoryQueue = Future<void>.value();
    final repository = ref.watch(settingsRepositoryProvider);
    return repository.loadActiveWorkspace();
  }

  /// Creates and persists a new workspace with [name], optionally unloading the current workspace and activating the new one.
  Future<AppWorkspace> createWorkspace(
    String name, {
    WebDavConfig? config,
    String? id,
    bool activate = false,
  }) {
    return _enqueueLifecycleWork(() async {
      _ensureMounted();
      if (activate) {
        await ref.read(workspaceUnloadCoordinatorProvider).runBeforeUnload();
        _ensureMounted();
      }
      return _enqueueRepositoryWork(() async {
        _ensureMounted();
        final repository = ref.read(settingsRepositoryProvider);
        final created = await repository.createWorkspace(
          name,
          config: config,
          id: id,
          activate: activate,
        );
        if (!ref.mounted) {
          return created;
        }
        if (activate) {
          _replaceLoadedWorkspace(created);
        }
        ref.read(_workspaceListRevisionProvider.notifier).bump();
        AppLogger.event(
          LogLevel.info,
          LogTag.lifecycle,
          'workspace.create',
          fields: <String, Object?>{
            'id': created.id,
            'name': created.name,
            'activated': activate,
          },
        );
        return created;
      });
    });
  }

  /// Deletes the workspace with [workspaceId] and loads the fallback workspace when the active workspace was deleted.
  Future<AppWorkspace> deleteWorkspace(String workspaceId) {
    return _enqueueLifecycleWork(() async {
      _ensureMounted();
      final previousId = state.asData?.value.id;
      final isDeletingActive =
          previousId == null || previousId == workspaceId.trim();
      if (isDeletingActive) {
        await ref.read(workspaceUnloadCoordinatorProvider).runBeforeUnload();
        _ensureMounted();
      }
      return _enqueueRepositoryWork(() async {
        _ensureMounted();
        final currentId = state.asData?.value.id;
        final repository = ref.read(settingsRepositoryProvider);
        final activeAfterDelete = await repository.deleteWorkspace(workspaceId);
        if (!ref.mounted) {
          return activeAfterDelete;
        }
        if (currentId == null || currentId != activeAfterDelete.id) {
          _replaceLoadedWorkspace(activeAfterDelete);
        }
        ref.read(_workspaceListRevisionProvider.notifier).bump();
        AppLogger.event(
          LogLevel.info,
          LogTag.lifecycle,
          'workspace.delete',
          fields: <String, Object?>{
            'deleted_id': workspaceId.trim(),
            'active_id': activeAfterDelete.id,
          },
        );
        return activeAfterDelete;
      });
    });
  }

  /// Renames the workspace with [workspaceId] to [newName] and updates in-memory state if it is currently active.
  Future<AppWorkspace> renameWorkspace(String workspaceId, String newName) {
    return _enqueueLifecycleWork(() {
      return _enqueueRepositoryWork(() async {
        _ensureMounted();
        final repository = ref.read(settingsRepositoryProvider);
        final renamed = await repository.renameWorkspace(workspaceId, newName);
        if (!ref.mounted) {
          return renamed;
        }
        if (state.asData?.value.id == renamed.id) {
          state = AsyncData<AppWorkspace>(renamed);
        }
        ref.read(_workspaceListRevisionProvider.notifier).bump();
        AppLogger.event(
          LogLevel.info,
          LogTag.lifecycle,
          'workspace.rename',
          fields: <String, Object?>{'id': renamed.id, 'name': renamed.name},
        );
        return renamed;
      });
    });
  }

  /// Unloads the current workspace from memory and loads the workspace with [workspaceId] as the active workspace.
  Future<AppWorkspace> switchWorkspace(String workspaceId) {
    return _enqueueLifecycleWork(() async {
      _ensureMounted();
      final trimmedTargetId = workspaceId.trim();
      final current = state.asData?.value;
      if (current != null && current.id == trimmedTargetId) {
        return current;
      }
      await ref.read(workspaceUnloadCoordinatorProvider).runBeforeUnload();
      _ensureMounted();
      return _enqueueRepositoryWork(() async {
        _ensureMounted();
        final latestCurrent = state.asData?.value;
        if (latestCurrent != null && latestCurrent.id == trimmedTargetId) {
          return latestCurrent;
        }
        final repository = ref.read(settingsRepositoryProvider);
        final nextWorkspace = await repository.activateWorkspace(workspaceId);
        if (!ref.mounted) {
          return nextWorkspace;
        }
        _replaceLoadedWorkspace(nextWorkspace);
        ref.read(_workspaceListRevisionProvider.notifier).bump();
        AppLogger.event(
          LogLevel.info,
          LogTag.lifecycle,
          'workspace.switch',
          fields: <String, Object?>{
            'from': latestCurrent?.id ?? 'none',
            'to': nextWorkspace.id,
            'name': nextWorkspace.name,
          },
        );
        return nextWorkspace;
      });
    });
  }

  /// Updates and persists [newConfig] for the currently active workspace.
  Future<void> updateActiveConfig(WebDavConfig newConfig) {
    return _enqueueRepositoryWork(() async {
      if (!ref.mounted) {
        return;
      }
      final previousSummary = state.asData?.value.summary;
      final repository = ref.read(settingsRepositoryProvider);
      await repository.saveConfig(newConfig);
      if (!ref.mounted) {
        return;
      }
      final reloaded = await repository.loadActiveWorkspace();
      if (!ref.mounted) {
        return;
      }
      state = AsyncData<AppWorkspace>(reloaded);
      if (previousSummary == null ||
          previousSummary.name != reloaded.name ||
          previousSummary.localFilePath != reloaded.config.localFilePath) {
        ref.read(_workspaceListRevisionProvider.notifier).bump();
      }
    });
  }

  /// Updates and persists [newConfig] specifically for [workspaceId] without overwriting another active workspace.
  Future<void> updateConfigForWorkspace(
    String workspaceId,
    WebDavConfig newConfig,
  ) {
    final normalizedId = workspaceId.trim();
    return _enqueueRepositoryWork(() async {
      if (!ref.mounted) {
        return;
      }
      final previousWorkspace = state.asData?.value;
      final repository = ref.read(settingsRepositoryProvider);
      await repository.saveConfigForWorkspace(normalizedId, newConfig);
      if (!ref.mounted) {
        return;
      }
      final reloaded = await repository.loadActiveWorkspace();
      if (!ref.mounted) {
        return;
      }
      if (reloaded.id == normalizedId) {
        state = AsyncData<AppWorkspace>(reloaded);
        final previousSummary = previousWorkspace?.summary;
        if (previousSummary == null ||
            previousWorkspace?.id != reloaded.id ||
            previousSummary.name != reloaded.name ||
            previousSummary.localFilePath != reloaded.config.localFilePath) {
          ref.read(_workspaceListRevisionProvider.notifier).bump();
        }
      } else {
        ref.read(_workspaceListRevisionProvider.notifier).bump();
      }
    });
  }

  /// Enqueues [action] onto the FIFO workspace lifecycle transition queue.
  Future<T> _enqueueLifecycleWork<T>(Future<T> Function() action) {
    return _enqueueOnQueue<T>(
      () => _lifecycleQueue,
      (nextTail) => _lifecycleQueue = nextTail,
      action,
    );
  }

  /// Enqueues [action] onto the FIFO queue selected by [getTail] and [setTail].
  Future<T> _enqueueOnQueue<T>(
    Future<void> Function() getTail,
    void Function(Future<void> nextTail) setTail,
    Future<T> Function() action,
  ) {
    final completer = Completer<T>();
    final nextTail = getTail().then((_) async {
      try {
        final result = await action();
        completer.complete(result);
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    setTail(nextTail);
    return completer.future;
  }

  /// Enqueues [action] onto the FIFO repository read/write queue.
  Future<T> _enqueueRepositoryWork<T>(Future<T> Function() action) {
    return _enqueueOnQueue<T>(
      () => _repositoryQueue,
      (nextTail) => _repositoryQueue = nextTail,
      action,
    );
  }

  /// Throws a [WorkspaceException] if this notifier was disposed before a workspace transition could run.
  void _ensureMounted() {
    if (!ref.mounted) {
      throw const WorkspaceException(
        WorkspaceErrorKind.settingsPersistenceFailed,
        'Workspace operation aborted because the workspace notifier was disposed.',
      );
    }
  }

  /// Replaces the loaded [AppWorkspace] snapshot directly with [nextWorkspace] without a transient `AsyncLoading` bounce.
  void _replaceLoadedWorkspace(AppWorkspace nextWorkspace) {
    state = AsyncData<AppWorkspace>(nextWorkspace);
  }
}

/// Coordinates pre-unload persistence flushes before [ActiveWorkspaceNotifier] unloads the active workspace.
class WorkspaceUnloadCoordinator {
  final Map<int, Future<void> Function()> _hooks =
      <int, Future<void> Function()>{};
  int _nextToken = 1;

  /// Registers [callback] to run before the active workspace is unloaded and returns an unregister handle.
  void Function() register(Future<void> Function() callback) {
    final token = _nextToken++;
    _hooks[token] = callback;
    return () {
      _hooks.remove(token);
    };
  }

  /// Invokes all currently registered pre-unload callbacks in registration order.
  Future<void> runBeforeUnload() async {
    final snapshot = List<Future<void> Function()>.of(_hooks.values);
    for (final callback in snapshot) {
      await callback();
    }
  }
}

/// Tracks revisions to the persisted workspace list so [workspaceSummariesProvider] refreshes without cyclic dependencies.
class _WorkspaceListRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// Increments the workspace list revision counter.
  void bump() {
    state++;
  }
}

/// Disables automatic Riverpod background retries so failed storage loads execute once until explicitly retried.
Duration? disableProviderRetry(int retryCount, Object error) => null;
