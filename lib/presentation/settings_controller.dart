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
import '../l10n/tier_localization_extension.dart';
import '../models/app_workspace.dart';
import '../models/settings_codec.dart';
import '../models/tdf_file_path.dart';
import '../models/webdav_config.dart';
import '../providers/config_providers.dart';
import '../providers/workspace_providers.dart';
import '../repositories/local_file_repository.dart';
import 'log_viewer_controller.dart';

/// Provides the presentation-layer [SettingsController] for storage paths, native pickers, and preference persistence.
final settingsControllerProvider = Provider<SettingsController>(
  SettingsController.new,
);

/// Reactive presentation wrapper exposing whether the active host platform supports native directory picking.
final supportsNativeDirectoryPickerProvider = Provider<bool>(
  (ref) => ref.watch(supportsDirectoryPickerProvider),
);

/// Sealed outcome returned by [SettingsController.savePreferenceChange].
sealed class SettingsPreferenceSaveResult {
  /// Creates a [SettingsPreferenceSaveResult].
  const SettingsPreferenceSaveResult();
}

/// Outcome returned when saving a settings preference fails with a [WorkspaceException].
@immutable
final class SettingsPreferenceSaveFailed extends SettingsPreferenceSaveResult {
  /// Creates a [SettingsPreferenceSaveFailed] with [localizedMessage].
  const SettingsPreferenceSaveFailed(this.localizedMessage);

  /// Localized error message formatted for display in the settings status banner.
  final String localizedMessage;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SettingsPreferenceSaveFailed &&
        other.localizedMessage == localizedMessage;
  }

  @override
  int get hashCode => localizedMessage.hashCode;
}

/// Outcome returned when a settings preference persists successfully.
@immutable
final class SettingsPreferenceSaved extends SettingsPreferenceSaveResult {
  /// Creates a [SettingsPreferenceSaved] carrying [effectiveConfig].
  const SettingsPreferenceSaved(this.effectiveConfig);

  /// Effective persisted [WebDavConfig] snapshot after the mutation.
  final WebDavConfig effectiveConfig;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SettingsPreferenceSaved &&
        other.effectiveConfig == effectiveConfig;
  }

  @override
  int get hashCode => effectiveConfig.hashCode;
}

/// Presentation controller decoupling settings screens and storage sections from repositories and native pickers.
class SettingsController {
  /// Creates a [SettingsController] backed by [_ref].
  const SettingsController(this._ref);

  static final RegExp _pathSeparatorPattern = RegExp(r'[/\\]');

  final Ref _ref;

  /// Whether the active host platform supports native directory picking.
  bool get supportsNativeDirectoryPicker =>
      _ref.read(supportsDirectoryPickerProvider);

  /// Consumes any one-shot startup settings recovery notice and returns its localized message, or `null`.
  String? consumeStartupRecoveryNotice({Locale? locale}) {
    final notice = _ref
        .read(settingsRepositoryProvider)
        .takeLastRecoveryNotice();
    if (notice == null) {
      return null;
    }
    final localizations = lookupAppLocalizations(
      locale ?? _ref.read(appLocaleProvider),
    );
    return switch (notice.kind) {
      SettingsRecoveryKind.recoveredFromBackup =>
        localizations.settingsRecoveredFromBackupNotice,
      SettingsRecoveryKind.resetAfterQuarantine =>
        localizations.settingsResetAfterQuarantineNotice,
    };
  }

  /// Lists sorted `.tdf` filenames discovered in the active local storage directory.
  List<String> listLocalTdfFileNames() =>
      _ref.read(localFileRepositoryProvider).listTdfFileNamesInDirectory();

  /// Opens the native directory picker for [config] and returns the combined destination path, or `null`.
  Future<String?> pickLocalDirectory(WebDavConfig config) async {
    final repository = _createRepository(config);
    final currentDirectory = repository.tryResolveDirectoryPath();
    final currentFileName = repository.extractFileName();
    final selectedDirectory = await _ref.read(directoryPickerProvider)(
      initialDirectory: currentDirectory,
    );
    if (selectedDirectory == null ||
        selectedDirectory.trim().isEmpty ||
        selectedDirectory == currentDirectory) {
      return null;
    }
    return TdfFilePath.combineDirectoryAndFileName(
      selectedDirectory,
      currentFileName,
    );
  }

  /// Opens the native file picker for [config] starting in its resolved directory.
  Future<String?> pickNativeLocalFile(WebDavConfig config) {
    final repository = _createRepository(config);
    return _ref.read(filePickerProvider)(
      initialDirectory: repository.tryResolveDirectoryPath(),
      currentFileName: repository.extractFileName(),
    );
  }

  /// Reads the presentation-layer [DiagnosticLogLevel] from [config].
  static DiagnosticLogLevel readLogLevel(WebDavConfig config) =>
      DiagnosticLogLevel.fromLogLevel(config.logLevel);

  /// Combines [chosenFileName] with the resolved directory of [config] when a base or explicit directory applies.
  String resolveChosenLocalFileName(
    WebDavConfig config,
    String chosenFileName,
  ) {
    final baseDirectoryPath = _ref.read(localStorageDirectoryPathProvider);
    final currentDirectory = _createRepository(config)
        .tryResolveDirectoryPath();
    final hasDirectory =
        _pathSeparatorPattern.hasMatch(config.localFilePath) ||
        baseDirectoryPath != null;
    return (hasDirectory && currentDirectory != null)
        ? TdfFilePath.combineDirectoryAndFileName(
            currentDirectory,
            chosenFileName,
          )
        : chosenFileName;
  }

  /// Resolves the preview filesystem path for [config], or returns `null` when invalid.
  String? resolvePreviewLocalPath(WebDavConfig config) =>
      _createRepository(config).tryResolveFilePath();

  /// Persists a settings preference transition from [previous] to [next], mapping [WorkspaceException] failures.
  Future<SettingsPreferenceSaveResult> savePreferenceChange({
    required WebDavConfig previous,
    required WebDavConfig next,
    Locale? locale,
  }) async {
    final notifier = _ref.read(webDavConfigProvider.notifier);
    try {
      if (next.diagnosticsEnabled != previous.diagnosticsEnabled) {
        await notifier.updateDiagnosticsEnabled(next.diagnosticsEnabled);
      } else if (next.dueLeadWindow != previous.dueLeadWindow) {
        await notifier.updateDueLeadWindow(next.dueLeadWindow);
      } else if (next.localWatchEnabled != previous.localWatchEnabled) {
        await notifier.updateLocalWatchEnabled(next.localWatchEnabled);
      } else if (next.logLevel != previous.logLevel) {
        await notifier.updateLogLevel(next.logLevel);
      } else if (next.logStorageMode != previous.logStorageMode) {
        await notifier.updateLogStorageMode(next.logStorageMode);
      } else {
        await notifier.updateConfig(next);
      }
      final effectiveConfig =
          _ref.read(webDavConfigProvider).asData?.value ?? next;
      return SettingsPreferenceSaved(effectiveConfig);
    } on WorkspaceException catch (error) {
      final localizations = lookupAppLocalizations(
        locale ?? _ref.read(appLocaleProvider),
      );
      return SettingsPreferenceSaveFailed(
        localizations.localizeWorkspaceError(error),
      );
    }
  }

  /// Returns a copy of [config] with [level] mapped to the underlying log threshold.
  static WebDavConfig withLogLevel(
    WebDavConfig config,
    DiagnosticLogLevel level,
  ) => config.copyWith(logLevel: level.toLogLevel());

  /// Constructs a [LocalFileRepository] scoped to [config] and current storage providers.
  LocalFileRepository _createRepository(WebDavConfig config) {
    return LocalFileRepository(
      config: config,
      baseDirectoryPath: _ref.read(localStorageDirectoryPathProvider),
      buildProfile: _ref.read(appBuildProfileProvider),
    );
  }
}
