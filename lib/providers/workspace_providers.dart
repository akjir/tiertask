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

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_workspace.dart';
import '../models/webdav_config.dart';
import '../services/app_logger.dart';
import 'task_providers.dart';

/// Provides the single currently loaded [AppWorkspace] in memory.
final activeWorkspaceProvider =
    AsyncNotifierProvider<ActiveWorkspaceNotifier, AppWorkspace>(
      ActiveWorkspaceNotifier.new,
    );

/// Provides lightweight [WorkspaceSummary] entries for all persisted workspaces.
final workspaceSummariesProvider = FutureProvider<List<WorkspaceSummary>>((
  ref,
) async {
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
  @override
  Future<AppWorkspace> build() async {
    final repository = ref.watch(settingsRepositoryProvider);
    return repository.loadActiveWorkspace();
  }

  /// Creates and persists a new workspace with [name], optionally unloading the current workspace and activating the new one.
  Future<AppWorkspace> createWorkspace(
    String name, {
    WebDavConfig? config,
    String? id,
    bool activate = false,
  }) async {
    if (activate) {
      await ref.read(workspaceUnloadCoordinatorProvider).runBeforeUnload();
    }
    final repository = ref.read(settingsRepositoryProvider);
    final created = await repository.createWorkspace(
      name,
      config: config,
      id: id,
      activate: activate,
    );
    if (activate) {
      _replaceLoadedWorkspace(created);
    }
    ref.read(_workspaceListRevisionProvider.notifier).bump();
    return created;
  }

  /// Deletes the workspace with [workspaceId] and loads the fallback workspace when the active workspace was deleted.
  Future<AppWorkspace> deleteWorkspace(String workspaceId) async {
    final previousId = state.asData?.value.id;
    final isDeletingActive =
        previousId == null || previousId == workspaceId.trim();
    if (isDeletingActive) {
      await ref.read(workspaceUnloadCoordinatorProvider).runBeforeUnload();
    }
    final repository = ref.read(settingsRepositoryProvider);
    final activeAfterDelete = await repository.deleteWorkspace(workspaceId);
    if (previousId == null || previousId != activeAfterDelete.id) {
      _replaceLoadedWorkspace(activeAfterDelete);
    }
    ref.read(_workspaceListRevisionProvider.notifier).bump();
    return activeAfterDelete;
  }

  /// Renames the workspace with [workspaceId] to [newName] and updates in-memory state if it is currently active.
  Future<AppWorkspace> renameWorkspace(
    String workspaceId,
    String newName,
  ) async {
    final repository = ref.read(settingsRepositoryProvider);
    final renamed = await repository.renameWorkspace(workspaceId, newName);
    if (state.asData?.value.id == renamed.id) {
      state = AsyncData(renamed);
    }
    ref.read(_workspaceListRevisionProvider.notifier).bump();
    return renamed;
  }

  /// Unloads the current workspace from memory and loads the workspace with [workspaceId] as the active workspace.
  Future<AppWorkspace> switchWorkspace(String workspaceId) async {
    final current = state.asData?.value;
    if (current != null && current.id == workspaceId.trim()) {
      return current;
    }
    await ref.read(workspaceUnloadCoordinatorProvider).runBeforeUnload();
    final repository = ref.read(settingsRepositoryProvider);
    final nextWorkspace = await repository.activateWorkspace(workspaceId);
    _replaceLoadedWorkspace(nextWorkspace);
    ref.read(_workspaceListRevisionProvider.notifier).bump();
    AppLogger.info(
      LogTag.lifecycle,
      'Switched active workspace to id=${nextWorkspace.id} name="${nextWorkspace.name}"',
    );
    return nextWorkspace;
  }

  /// Updates and persists [newConfig] for the currently active workspace.
  Future<void> updateActiveConfig(WebDavConfig newConfig) async {
    final repository = ref.read(settingsRepositoryProvider);
    await repository.saveConfig(newConfig);
    final reloaded = await repository.loadActiveWorkspace();
    state = AsyncData(reloaded);
    ref.read(_workspaceListRevisionProvider.notifier).bump();
  }

  /// Unloads the current [AppWorkspace] snapshot and replaces it with [nextWorkspace].
  void _replaceLoadedWorkspace(AppWorkspace nextWorkspace) {
    state = const AsyncLoading();
    state = AsyncData(nextWorkspace);
  }
}

/// Coordinates pre-unload persistence flushes before [ActiveWorkspaceNotifier] unloads the active workspace.
class WorkspaceUnloadCoordinator {
  Future<void> Function()? _onBeforeUnload;

  /// Registers the [callback] invoked before the active workspace is unloaded.
  void register(Future<void> Function() callback) {
    _onBeforeUnload = callback;
  }

  /// Invokes the registered pre-unload callback if present.
  Future<void> runBeforeUnload() async {
    if (_onBeforeUnload case final callback?) {
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
