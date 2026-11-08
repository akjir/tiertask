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
import '../models/app_workspace.dart';
import '../models/webdav_config.dart';
import '../repositories/app_version_repository.dart';
import '../repositories/link_launcher_repository.dart';
import '../repositories/local_file_repository.dart';
import '../repositories/webdav_repository.dart';
import '../services/app_logger.dart';
import '../services/tdf_service.dart';
import 'workspace_providers.dart';

/// Provides the effective [Locale] (`en` or `de`) based on [webDavConfigProvider] and OS locale.
final appLocaleProvider = Provider<Locale>((ref) {
  final language = resolveCurrentConfig(ref).language;
  return language.resolveLocale(PlatformDispatcher.instance.locale);
});

/// Provides the selected [AppThemeMode] (`system`, `light`, or `dark`) from [webDavConfigProvider].
final appThemeModeProvider = Provider<AppThemeMode>((ref) {
  return resolveCurrentConfig(ref).themeMode;
});

/// Provides the selected [AppThemePalette] (`slate` or `navy`) from [webDavConfigProvider].
final appThemePaletteProvider = Provider<AppThemePalette>((ref) {
  return resolveCurrentConfig(ref).themePalette;
});

/// Provides the resolved SemVer 2.0.0 application version and Git build metadata (`v0.1.0+<count>.<hash>[.dev]`).
final appVersionProvider = FutureProvider<String>((ref) async {
  return ref.watch(appVersionRepositoryProvider).loadAppVersion();
});

/// Provides the [AppVersionRepository] used to load the application version and build metadata.
final appVersionRepositoryProvider = Provider<AppVersionRepository>((ref) {
  return const PlatformAppVersionRepository();
});

/// Injectable clock function for deterministic date handling in unit tests.
final clockProvider = Provider<DateTime Function()>((ref) {
  return DateTime.now;
});

/// Provides whether opt-in diagnostic logging is enabled and synchronizes [AppLogger].
final diagnosticsEnabledProvider = Provider<bool>((ref) {
  final clock = ref.watch(clockProvider);
  final baseDirectoryPath = ref.watch(localStorageDirectoryPathProvider);
  final configAsync = ref.watch(webDavConfigProvider);
  final workspaceAsync = ref.watch(activeWorkspaceProvider);
  final versionAsync = ref.watch(appVersionProvider);
  final activeWorkspace = workspaceAsync.asData?.value;
  final resolvedConfig = configAsync.asData?.value ?? activeWorkspace?.config;
  AppLogger.clock = () => clock().toUtc();
  if (resolvedConfig == null) {
    return false;
  }

  final metadata = _buildLogMetadata(
    config: resolvedConfig,
    workspace: activeWorkspace,
    appVersion: versionAsync.asData?.value ?? '0.2.3',
  );
  final logFilePath = LocalFileRepository.resolveLogFilePath(
    baseDirectoryPath: baseDirectoryPath,
    utcNow: clock().toUtc(),
    platform: metadata.platform,
    workspaceId: metadata.workspaceId,
  );
  final resolvedBaseDir =
      baseDirectoryPath ?? LocalFileRepository.resolveDefaultDirectoryPath();
  if (resolvedConfig.diagnosticsEnabled || AppLogger.isEnabled) {
    AppLogger.setEnabled(
      resolvedConfig.diagnosticsEnabled,
      sink: const LocalFileLogSink(),
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

/// Provides a [LocalFileRepository] configured with the current [WebDavConfig].
final localFileRepositoryProvider = Provider<LocalFileRepository>((ref) {
  final config = resolveCurrentConfig(ref);
  final baseDirectoryPath = ref.watch(localStorageDirectoryPathProvider);
  final inMemoryStore = ref.watch(inMemoryLocalStoreProvider);
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
    );

/// Provides a [WebDavRepository] configured with the current [WebDavConfig].
final webDavRepositoryProvider = Provider<WebDavRepository>((ref) {
  final config = resolveCurrentConfig(ref);
  return WebDavRepository(config: config);
});

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
    final inMemoryStore = ref.read(inMemoryLocalStoreProvider);
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

  /// Uploads the active diagnostic log snapshot to WebDAV immediately.
  Future<void> syncLogToWebDavNow() async {
    final current = state.asData?.value ?? await future;
    if (!current.diagnosticsEnabled || !current.isWebDavConfigured) {
      return;
    }
    await ref
        .read(webDavRepositoryProvider)
        .saveLog(AppLogger.activeLogFileName);
  }

  /// Persists [newConfig] to the active workspace, synchronizes [AppLogger], and updates provider state.
  Future<void> updateConfig(WebDavConfig newConfig) async {
    await ref
        .read(activeWorkspaceProvider.notifier)
        .updateActiveConfig(newConfig);
    state = AsyncData(newConfig);
    _syncLoggerForConfig(newConfig);
    AppLogger.event(
      LogLevel.info,
      LogTag.lifecycle,
      'config.update',
      fields: <String, Object?>{
        'storage': newConfig.storageMode.name,
        'log_storage': newConfig.logStorageMode.name,
        'log_level': newConfig.logLevel.label,
        'tz_mode': newConfig.timeZoneMode.name,
      },
    );
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
        ref
            .read(webDavRepositoryProvider)
            .deleteLog(AppLogger.activeLogFileName),
      );
    }
    await updateConfig(updated);
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

  /// Synchronizes [AppLogger] state, path, and metadata for [config].
  void _syncLoggerForConfig(WebDavConfig config) {
    final baseDirectoryPath = ref.read(localStorageDirectoryPathProvider);
    final clock = ref.read(clockProvider);
    final activeWorkspace = ref.read(activeWorkspaceProvider).asData?.value;
    final appVersion = ref.read(appVersionProvider).asData?.value ?? '0.2.3';
    AppLogger.clock = () => clock().toUtc();
    final metadata = _buildLogMetadata(
      config: config,
      workspace: activeWorkspace,
      appVersion: appVersion,
    );
    final logFilePath = LocalFileRepository.resolveLogFilePath(
      baseDirectoryPath: baseDirectoryPath,
      utcNow: clock().toUtc(),
      platform: metadata.platform,
      workspaceId: metadata.workspaceId,
    );
    final resolvedBaseDir =
        baseDirectoryPath ?? LocalFileRepository.resolveDefaultDirectoryPath();
    if (!config.diagnosticsEnabled && !AppLogger.isEnabled) {
      return;
    }
    AppLogger.setEnabled(
      config.diagnosticsEnabled,
      sink: const LocalFileLogSink(),
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

/// Builds a [LogMetadata] snapshot from [config], [workspace], and [appVersion].
LogMetadata _buildLogMetadata({
  required WebDavConfig config,
  required AppWorkspace? workspace,
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
    workspaceId: workspace?.id ?? AppWorkspace.defaultId,
    workspaceName: workspace?.name ?? AppWorkspace.defaultName,
    storageMode: config.storageMode.name,
    logStorageMode: config.logStorageMode.name,
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
