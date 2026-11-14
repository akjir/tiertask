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

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_workspace.dart';
import '../repositories/local_file_repository.dart';
import 'config_providers.dart';
import 'sync_providers.dart';
import 'task_providers.dart';
import 'workspace_providers.dart';

/// Provides the trailing-edge debounce duration (`350 ms` by default) for external local `.tdf` watch events.
final localFileWatchDebounceProvider = Provider<Duration>(
  (ref) => LocalFileWatcherNotifier.defaultDebounce,
);

/// Resolves the scoped [LocalFileWatchTarget] for the active workspace and storage configuration.
final localFileWatchTargetProvider = Provider<LocalFileWatchTarget>((ref) {
  final workspace = ref.watch(activeWorkspaceProvider).asData?.value;
  final config =
      ref.watch(webDavConfigProvider).asData?.value ?? workspace?.config;
  final localRepo = ref.watch(localFileRepositoryProvider);
  final resolvedLocalWatchEnabled = workspace != null && config != null
      ? config.localWatchEnabled
      : null;
  final usesConfiguredLocal =
      resolvedLocalWatchEnabled == true &&
      config != null &&
      config.storageMode.usesLocal &&
      config.isLocalConfigured &&
      localRepo.canWatchDirectory;
  final filePath = usesConfiguredLocal ? localRepo.tryResolveFilePath() : null;
  final directoryPath = usesConfiguredLocal
      ? localRepo.tryResolveDirectoryPath()
      : null;
  final fileName = filePath != null
      ? LocalFileRepository.extractFileNameFromPath(filePath)
      : null;
  final enabled =
      usesConfiguredLocal && directoryPath != null && fileName != null;
  return LocalFileWatchTarget(
    workspaceId: workspace?.id ?? AppWorkspace.defaultId,
    directoryPath: directoryPath,
    fileName: fileName,
    enabled: enabled,
    resolvedLocalWatchEnabled: resolvedLocalWatchEnabled,
  );
});

/// Maintains the active parent-directory `.tdf` watch subscription and foreground catch-up listener.
final localFileWatcherProvider =
    NotifierProvider<LocalFileWatcherNotifier, void>(
      LocalFileWatcherNotifier.new,
    );

/// Immutable watch target snapshot scoping [LocalFileWatcherNotifier] rebuilds to relevant storage fields.
@immutable
class LocalFileWatchTarget {
  /// Creates a [LocalFileWatchTarget].
  const LocalFileWatchTarget({
    required this.workspaceId,
    required this.directoryPath,
    required this.fileName,
    required this.enabled,
    required this.resolvedLocalWatchEnabled,
  });

  /// Resolved parent directory path when local directory watching is active.
  final String? directoryPath;

  /// Whether parent-directory watching should be active for [workspaceId].
  final bool enabled;

  /// Target `.tdf` file name inside [directoryPath].
  final String? fileName;

  /// Resolved `localWatchEnabled` flag once workspace and configuration finish loading, or `null` while loading.
  final bool? resolvedLocalWatchEnabled;

  /// Active workspace identifier.
  final String workspaceId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalFileWatchTarget &&
          runtimeType == other.runtimeType &&
          directoryPath == other.directoryPath &&
          enabled == other.enabled &&
          fileName == other.fileName &&
          resolvedLocalWatchEnabled == other.resolvedLocalWatchEnabled &&
          workspaceId == other.workspaceId;

  @override
  int get hashCode => Object.hash(
    directoryPath,
    enabled,
    fileName,
    resolvedLocalWatchEnabled,
    workspaceId,
  );
}

/// Manages parent-directory `.tdf` watching, trailing-edge debouncing, and `AppLifecycleState.resumed` catch-up checks.
class LocalFileWatcherNotifier extends Notifier<void> {
  /// Default trailing-edge debounce window (`350 ms`) coalescing burst saves and atomic rename sequences.
  static const Duration defaultDebounce = Duration(milliseconds: 350);

  Timer? _debounceTimer;
  bool? _lastResolvedWatchEnabled;
  String? _lastWorkspaceId;
  AppLifecycleListener? _lifecycleListener;
  bool _streamClosed = false;
  int _watchGeneration = 0;
  StreamSubscription<void>? _watchSubscription;

  @override
  void build() {
    _disposeResources();
    ref.onDispose(_disposeResources);
    final target = ref.watch(localFileWatchTargetProvider);
    final debounce = ref.watch(localFileWatchDebounceProvider);
    _registerRebindListeners(target, debounce);
    final reEnabledInSameWorkspace = _updateToggleTracking(target);
    if (!target.enabled) {
      _watchGeneration++;
      return;
    }
    _bindWatchStream(debounce);
    _lifecycleListener = AppLifecycleListener(
      onStateChange: (lifecycleState) =>
          _handleLifecycleState(lifecycleState, target, debounce),
    );
    if (reEnabledInSameWorkspace) {
      _scheduleReconcile(_watchGeneration, debounce);
    }
  }

  /// Opens a parent-directory watch subscription and tracks stream completion for missing-directory rebinding.
  void _bindWatchStream(Duration debounce) {
    unawaited(_watchSubscription?.cancel());
    _watchSubscription = null;
    _streamClosed = false;
    final generation = ++_watchGeneration;
    _watchSubscription = ref
        .read(localFileRepositoryProvider)
        .watchTdfChanges()
        .listen(
          (_) => _scheduleReconcile(generation, debounce),
          onError: (_) {
            _streamClosed = true;
          },
          onDone: () {
            _streamClosed = true;
          },
        );
  }

  /// Cancels active timers, lifecycle listeners, and filesystem watch subscriptions.
  void _disposeResources() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
    unawaited(_watchSubscription?.cancel());
    _watchSubscription = null;
    _streamClosed = false;
  }

  /// Triggers a debounced catch-up check and optional stream rebind on [AppLifecycleState.resumed].
  void _handleLifecycleState(
    AppLifecycleState lifecycleState,
    LocalFileWatchTarget target,
    Duration debounce,
  ) {
    if (lifecycleState != AppLifecycleState.resumed || !target.enabled) {
      return;
    }
    _rebindIfClosed(target, debounce);
    _scheduleReconcile(_watchGeneration, debounce);
  }

  /// Rebinds the directory watch subscription if it previously closed and the target directory now exists.
  void _rebindIfClosed(LocalFileWatchTarget target, Duration debounce) {
    if (target.enabled &&
        _streamClosed &&
        ref.read(localFileRepositoryProvider).directoryExists()) {
      _bindWatchStream(debounce);
    }
  }

  /// Listens to board load and sync completion transitions to rebind missing directories created after startup.
  void _registerRebindListeners(
    LocalFileWatchTarget target,
    Duration debounce,
  ) {
    ref.listen<bool>(taskNotifierProvider.select((value) => value.hasValue), (
      _,
      hasValue,
    ) {
      if (hasValue) {
        _rebindIfClosed(target, debounce);
      }
    });
    ref.listen<DateTime?>(
      syncStateProvider.select((sync) => sync.lastSyncedAt),
      (_, _) => _rebindIfClosed(target, debounce),
    );
  }

  /// Schedules a trailing-edge debounced [TaskNotifier.reconcileExternalLocalChanges] pass for [generation].
  void _scheduleReconcile(int generation, Duration debounce) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      if (generation != _watchGeneration) {
        return;
      }
      unawaited(
        ref.read(taskNotifierProvider.notifier).reconcileExternalLocalChanges(),
      );
    });
  }

  /// Updates workspace and resolved toggle tracking, returning `true` only on an explicit `false -> true` toggle in the same workspace.
  bool _updateToggleTracking(LocalFileWatchTarget target) {
    if (_lastWorkspaceId != target.workspaceId) {
      _lastWorkspaceId = target.workspaceId;
      _lastResolvedWatchEnabled = null;
    }
    final reEnabledInSameWorkspace =
        _lastResolvedWatchEnabled == false &&
        target.resolvedLocalWatchEnabled == true &&
        target.enabled;
    if (target.resolvedLocalWatchEnabled != null) {
      _lastResolvedWatchEnabled = target.resolvedLocalWatchEnabled;
    }
    return reEnabledInSameWorkspace;
  }
}
