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
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../l10n/tier_localization_extension.dart';
import '../models/app_workspace.dart';
import '../models/webdav_config.dart';
import '../repositories/app_version_repository.dart';
import '../repositories/link_launcher_repository.dart';
import '../repositories/local_file_repository.dart';
import '../repositories/webdav_repository.dart';
import '../repositories/window_control_repository.dart';
import '../services/app_logger.dart';
import '../services/tdf_service.dart';
import 'workspace_providers.dart';

/// Provides the effective [Locale] (`en` or `de`) based on [webDavConfigProvider] and OS locale.
final appLocaleProvider = Provider<Locale>((ref) {
  final language =
      ref.watch(
        webDavConfigProvider.select(
          (asyncConfig) => asyncConfig.asData?.value.language,
        ),
      ) ??
      ref.watch(
        activeWorkspaceProvider.select(
          (asyncWorkspace) => asyncWorkspace.asData?.value.config.language,
        ),
      ) ??
      AppLanguage.system;
  return language.resolveLocale(PlatformDispatcher.instance.locale);
});

/// Provides the selected [AppThemeMode] (`system`, `light`, or `dark`) from [webDavConfigProvider].
final appThemeModeProvider = Provider<AppThemeMode>((ref) {
  return ref.watch(
        webDavConfigProvider.select(
          (asyncConfig) => asyncConfig.asData?.value.themeMode,
        ),
      ) ??
      ref.watch(
        activeWorkspaceProvider.select(
          (asyncWorkspace) => asyncWorkspace.asData?.value.config.themeMode,
        ),
      ) ??
      AppThemeMode.system;
});

/// Provides the selected [AppThemePalette] (`calm` or `plumUmber`) from [webDavConfigProvider].
final appThemePaletteProvider = Provider<AppThemePalette>((ref) {
  return ref.watch(
        webDavConfigProvider.select(
          (asyncConfig) => asyncConfig.asData?.value.themePalette,
        ),
      ) ??
      ref.watch(
        activeWorkspaceProvider.select(
          (asyncWorkspace) => asyncWorkspace.asData?.value.config.themePalette,
        ),
      ) ??
      AppThemePalette.calm;
});

/// Provides the resolved SemVer 2.0.0 application version and Git build metadata (`v0.1.0+<count>.<hash>[.dev]`).
final appVersionProvider = FutureProvider<String>((ref) async {
  return ref.watch(appVersionRepositoryProvider).loadAppVersion();
});

/// Provides the [AppVersionRepository] used to load the application version and build metadata.
final appVersionRepositoryProvider = Provider<AppVersionRepository>((ref) {
  return const PlatformAppVersionRepository();
});

/// Monotonic tick counter incremented when a wall-clock task boundary fires or
/// when the application resumes to the foreground.
final boundaryTickProvider = NotifierProvider<BoundaryTickNotifier, int>(
  BoundaryTickNotifier.new,
);

/// Injectable clock function for deterministic date handling in unit tests.
final clockProvider = Provider<DateTime Function()>((ref) {
  return DateTime.now;
});

/// Provides desktop custom-chrome window commands gated by [supportsDesktopWindowControlsProvider].
final desktopWindowActionsProvider = Provider<DesktopWindowActions>((ref) {
  return DesktopWindowActions(
    ref.watch(windowControlRepositoryProvider),
    isSupported: ref.watch(supportsDesktopWindowControlsProvider),
  );
});

/// Provides whether opt-in diagnostic logging is enabled and synchronizes [AppLogger].
final diagnosticsEnabledProvider = Provider<bool>((ref) {
  final clock = ref.watch(clockProvider);
  final baseDirectoryPath = ref.watch(localStorageDirectoryPathProvider);
  final buildProfile = ref.watch(appBuildProfileProvider);
  final workspaceMeta = ref.watch(
    activeWorkspaceProvider.select((workspaceAsync) {
      final workspace = workspaceAsync.asData?.value;
      if (workspace == null) {
        return null;
      }
      return (id: workspace.id, name: workspace.name);
    }),
  );
  final logSlice =
      ref.watch(
        webDavConfigProvider.select((asyncConfig) {
          final config = asyncConfig.asData?.value;
          return config == null ? null : _extractLoggerSlice(config);
        }),
      ) ??
      ref.watch(
        activeWorkspaceProvider.select((asyncWorkspace) {
          final config = asyncWorkspace.asData?.value.config;
          return config == null ? null : _extractLoggerSlice(config);
        }),
      );
  final appVersion =
      ref.watch(
        appVersionProvider.select((versionAsync) => versionAsync.asData?.value),
      ) ??
      '0.2.3';
  AppLogger.clock = () => clock().toUtc();
  if (logSlice == null) {
    return false;
  }

  final resolvedConfig = WebDavConfig(
    diagnosticsEnabled: logSlice.diagnosticsEnabled,
    logLevel: logSlice.logLevel,
    logStorageMode: logSlice.logStorageMode,
    password: logSlice.password,
    storageMode: logSlice.storageMode,
    language: logSlice.language,
    timeZoneMode: logSlice.timeZoneMode,
    manualTimeZoneOffsetMinutes: logSlice.manualTimeZoneOffsetMinutes,
    serverUrl: logSlice.serverUrl,
    username: logSlice.username,
    filePath: logSlice.filePath,
  );
  final metadata = _buildLogMetadata(
    config: resolvedConfig,
    workspaceId: workspaceMeta?.id ?? AppWorkspace.defaultId,
    workspaceName: workspaceMeta?.name ?? AppWorkspace.defaultName,
    appVersion: appVersion,
  );
  final logFilePath = LocalFileRepository.resolveLogFilePath(
    baseDirectoryPath: baseDirectoryPath,
    utcNow: clock().toUtc(),
    platform: metadata.platform,
    workspaceId: metadata.workspaceId,
    buildProfile: buildProfile,
  );
  final resolvedBaseDir =
      baseDirectoryPath ??
      LocalFileRepository.resolveDefaultDirectoryPath(
        buildProfile: buildProfile,
      );
  if (resolvedConfig.diagnosticsEnabled || AppLogger.isEnabled) {
    AppLogger.setEnabled(
      resolvedConfig.diagnosticsEnabled,
      sink: LocalFileLogSink(buildProfile: buildProfile),
      logFilePath: logFilePath,
      baseDirectoryPath: resolvedBaseDir,
      secretToRedact: resolvedConfig.password,
      minimumLevel: resolvedConfig.logLevel,
      metadata: metadata,
      persistToDisk: resolvedConfig.logStorageMode.usesLocal,
    );
  }

  Timer? debounceTimer;
  void onLogRevisionChanged() {
    if (!resolvedConfig.diagnosticsEnabled ||
        !resolvedConfig.logStorageMode.usesWebDav ||
        !resolvedConfig.isWebDavConfigured) {
      return;
    }
    debounceTimer?.cancel();
    debounceTimer = Timer(AppLogger.webDavFlushDebounce, () {
      unawaited(_flushLogToWebDavQuietly(ref));
    });
  }

  AppLogger.revision.addListener(onLogRevisionChanged);
  ref.onDispose(() {
    debounceTimer?.cancel();
    AppLogger.revision.removeListener(onLogRevisionChanged);
  });

  return resolvedConfig.diagnosticsEnabled;
});

/// Provides the native directory picker function, overridable in widget tests.
final directoryPickerProvider =
    Provider<Future<String?> Function({String? initialDirectory})>((ref) {
      return ({String? initialDirectory}) => ref
          .read(localFileRepositoryProvider)
          .pickDirectory(initialDirectory: initialDirectory);
    });

/// Provides the native file picker function for selecting or creating a `.tdf` file, overridable in widget tests.
final filePickerProvider =
    Provider<
      Future<String?> Function({
        String? initialDirectory,
        String? currentFileName,
      })
    >((ref) {
      return ({String? initialDirectory, String? currentFileName}) => ref
          .read(localFileRepositoryProvider)
          .pickTdfFile(
            initialDirectory: initialDirectory,
            currentFileName: currentFileName,
          );
    });

/// Provides an isolated in-memory file map for hermetic widget tests.
final inMemoryLocalStoreProvider = Provider<Map<String, String>>((ref) {
  return <String, String>{};
});

/// Provides the [LinkLauncherRepository] for opening task link URIs via the OS handler.
final linkLauncherRepositoryProvider = Provider<LinkLauncherRepository>((ref) {
  return const PlatformLinkLauncherRepository();
});

/// Provides a [LocalFileRepository] configured with the current local storage binding.
final localFileRepositoryProvider = Provider<LocalFileRepository>((ref) {
  final localSlice =
      ref.watch(
        webDavConfigProvider.select((asyncConfig) {
          final config = asyncConfig.asData?.value;
          if (config == null) {
            return null;
          }
          return (
            localFilePath: config.localFilePath,
            language: config.language,
            storageMode: config.storageMode,
          );
        }),
      ) ??
      ref.watch(
        activeWorkspaceProvider.select((asyncWorkspace) {
          final config = asyncWorkspace.asData?.value.config;
          if (config == null) {
            return null;
          }
          return (
            localFilePath: config.localFilePath,
            language: config.language,
            storageMode: config.storageMode,
          );
        }),
      );
  final config = localSlice == null
      ? const WebDavConfig()
      : WebDavConfig(
          localFilePath: localSlice.localFilePath,
          language: localSlice.language,
          storageMode: localSlice.storageMode,
        );
  final baseDirectoryPath = ref.watch(localStorageDirectoryPathProvider);
  final buildProfile = ref.watch(appBuildProfileProvider);
  final inMemoryStore = ref.watch(inMemoryLocalStoreProvider);
  return LocalFileRepository(
    config: config,
    baseDirectoryPath: baseDirectoryPath,
    buildProfile: buildProfile,
    inMemoryStore: inMemoryStore,
  );
});

/// Optional base directory path override for [LocalFileRepository] in tests.
final localStorageDirectoryPathProvider = Provider<String?>((ref) {
  return null;
});

/// Provides a safe external link launcher returning `true` on success and `false` on [LinkLaunchException].
final openExternalLinkProvider = Provider<Future<bool> Function(String uri)>((
  ref,
) {
  final repository = ref.watch(linkLauncherRepositoryProvider);
  return (String uri) async {
    try {
      await repository.openLink(uri);
      return true;
    } on LinkLaunchException {
      return false;
    }
  };
});

/// Whether the host platform uses custom desktop window chrome (`true` on Linux and Windows, `false` on Android).
final supportsDesktopWindowControlsProvider = Provider<bool>((ref) {
  return defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows;
});

/// Whether the host platform supports changing the local `.tdf` directory via a native picker (`true` on Linux and Windows, `false` on Android).
final supportsDirectoryPickerProvider = Provider<bool>((ref) {
  return defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows;
});

/// Provides the stateless [TdfService] scanner, parser, and serializer.
final tdfServiceProvider = Provider<TdfService>((ref) {
  return const TdfService();
});

/// Provides the persisted [WebDavConfig] state.
final webDavConfigProvider =
    AsyncNotifierProvider<WebDavConfigNotifier, WebDavConfig>(
      WebDavConfigNotifier.new,
      retry: disableProviderRetry,
    );

/// Provides a [WebDavRepository] configured with the current WebDAV binding so unrelated preference edits preserve ETag caches.
final webDavRepositoryProvider = Provider<WebDavRepository>((ref) {
  final remoteSlice =
      ref.watch(
        webDavConfigProvider.select((asyncConfig) {
          final config = asyncConfig.asData?.value;
          if (config == null) {
            return null;
          }
          return (
            serverUrl: config.serverUrl,
            username: config.username,
            password: config.password,
            filePath: config.filePath,
            language: config.language,
            storageMode: config.storageMode,
          );
        }),
      ) ??
      ref.watch(
        activeWorkspaceProvider.select((asyncWorkspace) {
          final config = asyncWorkspace.asData?.value.config;
          if (config == null) {
            return null;
          }
          return (
            serverUrl: config.serverUrl,
            username: config.username,
            password: config.password,
            filePath: config.filePath,
            language: config.language,
            storageMode: config.storageMode,
          );
        }),
      );
  final config = remoteSlice == null
      ? const WebDavConfig()
      : WebDavConfig(
          serverUrl: remoteSlice.serverUrl,
          username: remoteSlice.username,
          password: remoteSlice.password,
          filePath: remoteSlice.filePath,
          language: remoteSlice.language,
          storageMode: remoteSlice.storageMode,
        );
  return WebDavRepository(config: config);
});

/// Provides the [WindowControlRepository] driving frameless desktop window commands.
final windowControlRepositoryProvider = Provider<WindowControlRepository>((
  ref,
) {
  return const PlatformWindowControlRepository();
});

/// Monotonic state notifier backing [boundaryTickProvider].
class BoundaryTickNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// Advances the reactive boundary tick counter by one.
  void increment() {
    state++;
  }
}

/// Mediates desktop custom-chrome window commands between `lib/ui/` and [WindowControlRepository].
class DesktopWindowActions {
  /// Creates a [DesktopWindowActions] facade backed by [_repository] with [isSupported] platform gating.
  const DesktopWindowActions(this._repository, {required this.isSupported});

  /// Whether the host platform enables custom desktop window controls (`true` on Linux and Windows, `false` on Android).
  final bool isSupported;

  final WindowControlRepository _repository;

  /// Requests a graceful application window close on supported desktop platforms.
  Future<void> closeWindow() async {
    if (!isSupported) {
      return;
    }
    await _repository.closeWindow();
  }

  /// Starts a native desktop window move drag on supported desktop platforms.
  Future<void> startDragging() async {
    if (!isSupported) {
      return;
    }
    await _repository.startDragging();
  }

  /// Toggles maximized/restored state on supported desktop platforms.
  Future<void> toggleMaximize() async {
    if (!isSupported) {
      return;
    }
    await _repository.toggleMaximize();
  }
}

/// Manages the persisted [WebDavConfig] state for the currently active workspace.
class WebDavConfigNotifier extends AsyncNotifier<WebDavConfig> {
  String? _activeWorkspaceId;
  int _inFlightWriteCount = 0;
  bool _initialBuildPending = false;
  WebDavConfig? _lastPersistedConfig;
  Future<void> _pendingWrite = Future<void>.value();
  int _writeGeneration = 0;

  @override
  FutureOr<WebDavConfig> build() {
    _inFlightWriteCount = 0;
    _initialBuildPending = false;
    _writeGeneration = 0;
    _pendingWrite = Future<void>.value();
    ref.listen<AsyncValue<AppWorkspace>>(
      activeWorkspaceProvider,
      _handleActiveWorkspaceChanged,
    );
    final workspaceAsync = ref.read(activeWorkspaceProvider);
    return switch (workspaceAsync) {
      AsyncData<AppWorkspace>(:final value) => _seedLoadedWorkspace(value),
      AsyncError<AppWorkspace>(:final error, :final stackTrace) =>
        Error.throwWithStackTrace(error, stackTrace),
      AsyncLoading<AppWorkspace>() => _awaitInitialWorkspace(),
    };
  }

  /// Moves the local `.tdf` file when its resolved path changes and persists [newConfig] atomically.
  Future<void> changeLocalFileLocation(WebDavConfig newConfig) async {
    final current = state.asData?.value ?? await future;
    final localizations = lookupAppLocalizations(
      newConfig.language.resolveLocale(PlatformDispatcher.instance.locale),
    );
    final baseDirectoryPath = ref.read(localStorageDirectoryPathProvider);
    final buildProfile = ref.read(appBuildProfileProvider);
    final inMemoryStore = ref.read(inMemoryLocalStoreProvider);
    final sourceRepo = LocalFileRepository(
      config: current,
      baseDirectoryPath: baseDirectoryPath,
      buildProfile: buildProfile,
      inMemoryStore: inMemoryStore,
    );
    final targetRepo = LocalFileRepository(
      config: newConfig,
      baseDirectoryPath: baseDirectoryPath,
      buildProfile: buildProfile,
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
      throw LocalFileException(
        localizations.localizeWorkspaceError(error),
        cause: error,
      );
    } on Object {
      if (shouldMove) {
        await _tryRollbackMove(targetRepo, sourceRepo);
      }
      rethrow;
    }
  }

  /// Uploads the active diagnostic log snapshot to WebDAV immediately.
  Future<void> syncLogToWebDavNow() async {
    final current = state.asData?.value ?? await future;
    if (!current.diagnosticsEnabled || !current.isWebDavConfigured) {
      return;
    }
    await WebDavRepository(config: current)
        .saveLog(AppLogger.activeLogFileName);
  }

  /// Persists [newConfig] to the active workspace in FIFO order with optimistic state updates and rollback on failure.
  Future<void> updateConfig(WebDavConfig newConfig) {
    final previous = state.asData?.value;
    final rollbackConfig = _lastPersistedConfig ?? previous;
    final generation = ++_writeGeneration;
    _inFlightWriteCount++;
    if (ref.mounted && previous != newConfig) {
      state = AsyncData<WebDavConfig>(newConfig);
      if (previous == null ||
          _extractLoggerSlice(previous) != _extractLoggerSlice(newConfig)) {
        _syncLoggerForConfig(newConfig);
      }
    }

    final completer = Completer<void>();
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        await ref
            .read(activeWorkspaceProvider.notifier)
            .updateActiveConfig(newConfig);
        if (ref.mounted) {
          _lastPersistedConfig = newConfig;
        }
        AppLogger.event(
          LogLevel.info,
          LogTag.lifecycle,
          'config.update',
          fields: <String, Object?>{
            'storage': newConfig.storageMode.name,
            'local_watch': newConfig.localWatchEnabled,
            'due_lead': newConfig.dueLeadWindow.name,
            'log_storage': newConfig.logStorageMode.name,
            'log_level': newConfig.logLevel.label,
            'tz_mode': newConfig.timeZoneMode.name,
          },
        );
        completer.complete();
      } on Object catch (error, stackTrace) {
        if (ref.mounted &&
            generation == _writeGeneration &&
            rollbackConfig != null) {
          state = AsyncData<WebDavConfig>(rollbackConfig);
          if (_extractLoggerSlice(newConfig) !=
              _extractLoggerSlice(rollbackConfig)) {
            _syncLoggerForConfig(rollbackConfig);
          }
        }
        completer.completeError(error, stackTrace);
      } finally {
        _inFlightWriteCount = _inFlightWriteCount > 0
            ? _inFlightWriteCount - 1
            : 0;
      }
    });
    return completer.future;
  }

  /// Updates the [diagnosticsEnabled] preference, synchronizes [AppLogger], and persists it immediately.
  Future<void> updateDiagnosticsEnabled(bool diagnosticsEnabled) async {
    final current = state.asData?.value ?? await future;
    final updated = current.copyWith(diagnosticsEnabled: diagnosticsEnabled);
    _syncLoggerForConfig(updated);
    if (!diagnosticsEnabled &&
        current.logStorageMode.usesWebDav &&
        current.isWebDavConfigured) {
      unawaited(
        WebDavRepository(config: current)
            .deleteLog(AppLogger.activeLogFileName),
      );
    }
    await updateConfig(updated);
  }

  /// Updates only the per-workspace [dueLeadWindow] preference and persists it immediately.
  Future<void> updateDueLeadWindow(DueLeadWindow dueLeadWindow) async {
    final current = state.asData?.value ?? await future;
    final updated = current.copyWith(dueLeadWindow: dueLeadWindow);
    await updateConfig(updated);
  }

  /// Updates only the display [language] preference and persists it immediately.
  Future<void> updateLanguage(AppLanguage language) async {
    final current = state.asData?.value ?? await future;
    final updated = current.copyWith(language: language);
    await updateConfig(updated);
  }

  /// Updates only the [localWatchEnabled] preference and persists it immediately.
  Future<void> updateLocalWatchEnabled(bool localWatchEnabled) async {
    final current = state.asData?.value ?? await future;
    final updated = current.copyWith(localWatchEnabled: localWatchEnabled);
    await updateConfig(updated);
  }

  /// Updates only the [locationEnabled] preference and persists it immediately.
  Future<void> updateLocationEnabled(bool locationEnabled) async {
    final current = state.asData?.value ?? await future;
    final updated = current.copyWith(locationEnabled: locationEnabled);
    await updateConfig(updated);
  }

  /// Updates the minimum [logLevel] threshold, refreshes [AppLogger], and persists it immediately.
  Future<void> updateLogLevel(LogLevel logLevel) async {
    final current = state.asData?.value ?? await future;
    final updated = current.copyWith(logLevel: logLevel);
    AppLogger.setMinimumLevel(logLevel);
    await updateConfig(updated);
  }

  /// Updates the [logStorageMode] target, synchronizes [AppLogger], and persists it immediately.
  Future<void> updateLogStorageMode(StorageMode logStorageMode) async {
    final current = state.asData?.value ?? await future;
    final updated = current.copyWith(logStorageMode: logStorageMode);
    await updateConfig(updated);
    if (updated.diagnosticsEnabled &&
        logStorageMode.usesWebDav &&
        updated.isWebDavConfigured) {
      unawaited(syncLogToWebDavNow());
    }
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

  /// Awaits the initial [activeWorkspaceProvider] load without colliding with [_handleActiveWorkspaceChanged].
  Future<WebDavConfig> _awaitInitialWorkspace() async {
    _initialBuildPending = true;
    try {
      final workspace = await ref.read(activeWorkspaceProvider.future);
      return _seedLoadedWorkspace(workspace);
    } finally {
      _initialBuildPending = false;
    }
  }

  /// Synchronizes [state] reactively when [activeWorkspaceProvider] changes without bouncing through `AsyncLoading` on config saves.
  void _handleActiveWorkspaceChanged(
    AsyncValue<AppWorkspace>? previous,
    AsyncValue<AppWorkspace> next,
  ) {
    if (_initialBuildPending) {
      return;
    }
    switch (next) {
      case AsyncData<AppWorkspace>(:final value):
        final switchedWorkspace =
            _activeWorkspaceId != null && _activeWorkspaceId != value.id;
        _activeWorkspaceId = value.id;
        _lastPersistedConfig = value.config;
        if (_inFlightWriteCount > 0 && !switchedWorkspace) {
          return;
        }
        if (state.asData?.value != value.config) {
          state = AsyncData<WebDavConfig>(value.config);
        }
      case AsyncError<AppWorkspace>(:final error, :final stackTrace):
        state = AsyncError<WebDavConfig>(error, stackTrace);
      case AsyncLoading<AppWorkspace>():
        if (previous?.hasValue ?? false) {
          state = const AsyncLoading<WebDavConfig>();
        }
    }
  }

  /// Records the initial loaded [workspace] identifier and persisted config baseline.
  WebDavConfig _seedLoadedWorkspace(AppWorkspace workspace) {
    _activeWorkspaceId = workspace.id;
    _lastPersistedConfig = workspace.config;
    if (_writeGeneration > 0) {
      return state.asData?.value ?? workspace.config;
    }
    return workspace.config;
  }

  /// Synchronizes [AppLogger] state, path, and metadata for [config].
  void _syncLoggerForConfig(WebDavConfig config) {
    final baseDirectoryPath = ref.read(localStorageDirectoryPathProvider);
    final buildProfile = ref.read(appBuildProfileProvider);
    final clock = ref.read(clockProvider);
    final activeWorkspace = ref.read(activeWorkspaceProvider).asData?.value;
    final appVersion = ref.read(appVersionProvider).asData?.value ?? '0.2.3';
    AppLogger.clock = () => clock().toUtc();
    final metadata = _buildLogMetadata(
      config: config,
      workspaceId: activeWorkspace?.id ?? AppWorkspace.defaultId,
      workspaceName: activeWorkspace?.name ?? AppWorkspace.defaultName,
      appVersion: appVersion,
    );
    final logFilePath = LocalFileRepository.resolveLogFilePath(
      baseDirectoryPath: baseDirectoryPath,
      utcNow: clock().toUtc(),
      platform: metadata.platform,
      workspaceId: metadata.workspaceId,
      buildProfile: buildProfile,
    );
    final resolvedBaseDir =
        baseDirectoryPath ??
        LocalFileRepository.resolveDefaultDirectoryPath(
          buildProfile: buildProfile,
        );
    if (!config.diagnosticsEnabled && !AppLogger.isEnabled) {
      return;
    }
    AppLogger.setEnabled(
      config.diagnosticsEnabled,
      sink: LocalFileLogSink(buildProfile: buildProfile),
      logFilePath: logFilePath,
      baseDirectoryPath: resolvedBaseDir,
      secretToRedact: config.password,
      minimumLevel: config.logLevel,
      metadata: metadata,
      persistToDisk: config.logStorageMode.usesLocal,
    );
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

/// Reads the active [WebDavConfig] synchronously without registering reactive provider subscriptions.
WebDavConfig readCurrentConfig(Ref ref) {
  final configAsync = ref.read(webDavConfigProvider);
  if (configAsync.asData?.value case final config?) {
    return config;
  }
  final workspaceAsync = ref.read(activeWorkspaceProvider);
  return workspaceAsync.asData?.value.config ?? const WebDavConfig();
}

/// Resolves the active [WebDavConfig] synchronously from [webDavConfigProvider] or [activeWorkspaceProvider].
WebDavConfig resolveCurrentConfig(Ref ref) {
  final configAsync = ref.watch(webDavConfigProvider);
  if (configAsync.asData?.value case final config?) {
    return config;
  }
  final workspaceAsync = ref.watch(activeWorkspaceProvider);
  return workspaceAsync.asData?.value.config ?? const WebDavConfig();
}

/// Builds a [LogMetadata] snapshot from [config], workspace identity, and [appVersion].
LogMetadata _buildLogMetadata({
  required WebDavConfig config,
  required String workspaceId,
  required String workspaceName,
  required String appVersion,
}) {
  final locale = config.language.resolveLocale(
    PlatformDispatcher.instance.locale,
  );
  final timeZoneSummary = config.timeZoneMode == AppTimeZoneMode.manual
      ? 'manual (${WebDavConfig.formatUtcOffset(config.manualTimeZoneOffsetMinutes)})'
      : 'automatic';
  return LogMetadata(
    appVersion: appVersion,
    platform: LocalFileRepository.hostPlatform,
    osVersion: LocalFileRepository.hostOsVersion,
    locale: locale.toLanguageTag(),
    timeZone: timeZoneSummary,
    workspaceId: workspaceId,
    workspaceName: workspaceName,
    storageMode: config.storageMode.name,
    logStorageMode: config.logStorageMode.name,
  );
}

/// Extracts only the [WebDavConfig] fields that affect [AppLogger] configuration and metadata.
({
  bool diagnosticsEnabled,
  LogLevel logLevel,
  StorageMode logStorageMode,
  String password,
  StorageMode storageMode,
  AppLanguage language,
  AppTimeZoneMode timeZoneMode,
  int manualTimeZoneOffsetMinutes,
  String serverUrl,
  String username,
  String filePath,
})
_extractLoggerSlice(WebDavConfig config) {
  return (
    diagnosticsEnabled: config.diagnosticsEnabled,
    logLevel: config.logLevel,
    logStorageMode: config.logStorageMode,
    password: config.password,
    storageMode: config.storageMode,
    language: config.language,
    timeZoneMode: config.timeZoneMode,
    manualTimeZoneOffsetMinutes: config.manualTimeZoneOffsetMinutes,
    serverUrl: config.serverUrl,
    username: config.username,
    filePath: config.filePath,
  );
}

/// Uploads the active diagnostic log to WebDAV in the background, ignoring errors.
Future<void> _flushLogToWebDavQuietly(Ref ref) async {
  try {
    await ref
        .read(webDavRepositoryProvider)
        .saveLog(AppLogger.activeLogFileName);
  } on Object {
    // Background log upload errors are already recorded by WebDavRepository.
  }
}
