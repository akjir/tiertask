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
import '../l10n/storage_file_read_localization_extension.dart';
import '../l10n/tier_localization_extension.dart';
import '../models/app_workspace.dart';
import '../models/tdf_file_path.dart';
import '../models/webdav_config.dart';
import '../repositories/local_file_repository.dart';
import '../repositories/webdav_repository.dart';
import '../services/app_logger.dart';
import 'config_providers.dart';
import 'shell_providers.dart';
import 'sync_providers.dart';
import 'task_providers.dart';
import 'ui_telemetry.dart';
import 'workspace_providers.dart';

/// Provides transient WebDAV draft inputs, validation errors, status banners,
/// and capability-gated storage operations for the Settings view (`U-UX-006`).
final settingsDraftProvider =
    NotifierProvider.autoDispose<SettingsDraftNotifier, SettingsDraftState>(
      SettingsDraftNotifier.new,
    );

/// Semantic visual tone for the top status banner inside the Settings view.
enum SettingsBannerTone {
  /// Amber warning status banner.
  warning,

  /// Crimson danger or validation error status banner.
  danger,

  /// Green confirmation status banner.
  success,
}

/// Distinguishes blocking asynchronous WebDAV and storage operations inside [SettingsDraftNotifier].
enum SettingsBusyOperation {
  /// No blocking WebDAV or storage operation is running.
  idle,

  /// Explicit WebDAV draft credentials are being validated and persisted.
  saveWebDav,

  /// WebDAV connectivity and synchronization are actively running.
  testConnectionAndSync,

  /// A local or remote `.tdf` file move, rename, select, or wipe is running.
  storageOperation,
}

/// Coordinates transient WebDAV draft state, explicit validation, silent draft discard,
/// non-blocking preference persistence, and capability-gated local/remote file actions.
class SettingsDraftNotifier extends Notifier<SettingsDraftState> {
  static final RegExp _pathSeparatorPattern = RegExp(r'[/\\]');

  String? _activeWorkspaceId;

  /// Whether any inline WebDAV validation error is currently set on [state].
  bool get _hasValidationErrors =>
      state.serverUrlError != null ||
      state.usernameError != null ||
      state.passwordError != null ||
      state.filePathError != null;

  @override
  SettingsDraftState build() {
    final initialConfig = readCurrentConfig(ref);
    _activeWorkspaceId = ref.read(activeWorkspaceProvider).asData?.value.id;
    final initialLocalPathPreview = ref
        .read(localFileRepositoryProvider)
        .tryResolveFilePath();

    ref.listen<String?>(
      activeWorkspaceProvider.select((workspace) => workspace.asData?.value.id),
      _handleWorkspaceIdChanged,
    );

    ref.listen<_WebDavConfigSlice?>(
      webDavConfigProvider.select((asyncConfig) {
        final config = asyncConfig.asData?.value;
        if (config == null) {
          return null;
        }
        return (
          filePath: config.filePath,
          password: config.password,
          serverUrl: config.serverUrl,
          storageMode: config.storageMode,
          username: config.username,
        );
      }),
      _handleWebDavConfigSliceChanged,
    );

    ref.listen<String?>(
      localFileRepositoryProvider.select(
        (repository) => repository.tryResolveFilePath(),
      ),
      _handleResolvedLocalPathChanged,
    );

    ref.listen<ShellView>(
      shellProvider.select((shell) => shell.view),
      _handleShellViewChanged,
    );

    return SettingsDraftState(
      serverUrl: initialConfig.serverUrl,
      username: initialConfig.username,
      password: initialConfig.password,
      filePath: _normalizePersistedFilePath(initialConfig.filePath),
      resolvedLocalPathPreview: initialLocalPathPreview,
    );
  }

  /// Discards unsaved WebDAV edits, re-hydrates from persisted config, and clears validation errors and banner.
  void discardWebDavDraft({String reason = 'manual'}) {
    if (state.isDirty) {
      UiTelemetry.logSettingsWebDavDraftDiscarded(reason);
    }
    final persisted = readCurrentConfig(ref);
    state = state.copyWith(
      serverUrl: persisted.serverUrl,
      username: persisted.username,
      password: persisted.password,
      filePath: _normalizePersistedFilePath(persisted.filePath),
      isDirty: false,
      clearServerUrlError: true,
      clearUsernameError: true,
      clearPasswordError: true,
      clearFilePathError: true,
      clearStatusBanner: true,
    );
  }

  /// Dismisses the currently displayed settings status banner.
  void dismissStatusBanner() {
    if (state.statusBanner == null) {
      return;
    }
    state = state.copyWith(clearStatusBanner: true);
  }

  /// Lists sorted `.tdf` filenames discovered in the active local storage directory.
  List<String> listLocalTdfFileNames() =>
      ref.read(localFileRepositoryProvider).listTdfFileNamesInDirectory();

  /// Moves the active local `.tdf` file to a user-picked directory when native directory picking is supported.
  Future<ActionResult> moveLocalDirectory({Locale? locale}) async {
    if (state.isBusy) {
      return const ActionSucceeded();
    }
    final localizations = _resolveLocalizations(locale);
    if (!ref.read(supportsDirectoryPickerProvider)) {
      return ActionValidationFailed(
        message: localizations.settingsMoveDesktopOnlyTooltip,
      );
    }

    final previousConfig = readCurrentConfig(ref);
    return _runGuardedAction(
      operation: SettingsBusyOperation.storageOperation,
      localizations: localizations,
      successMessage: localizations.localDirectoryMovedBanner,
      action: () async {
        final repository = _createLocalRepository(previousConfig);
        final currentDirectory = repository.tryResolveDirectoryPath();
        final currentFileName = repository.extractFileName();
        final selectedDirectory = await ref.read(directoryPickerProvider)(
          initialDirectory: currentDirectory,
        );
        if (selectedDirectory == null ||
            selectedDirectory.trim().isEmpty ||
            selectedDirectory == currentDirectory) {
          return false;
        }
        final targetPath = LocalFileRepository.combineDirectoryAndFileName(
          selectedDirectory,
          currentFileName,
        );
        final candidateConfig = previousConfig.copyWith(
          localFilePath: targetPath.trim(),
        );
        await ref
            .read(webDavConfigProvider.notifier)
            .changeLocalFileLocation(candidateConfig);
        return true;
      },
    );
  }

  /// Validates [rawFileName] and renames the local `.tdf` file within its current directory.
  Future<ActionResult> renameLocalFile(
    String rawFileName, {
    Locale? locale,
  }) async {
    if (state.isBusy) {
      return const ActionSucceeded();
    }
    final localizations = _resolveLocalizations(locale);
    if (!_isValidLocalSingleFileName(rawFileName)) {
      return _failLocalFileNameValidation(localizations);
    }

    final previousConfig = readCurrentConfig(ref);
    final normalizedFileName = TdfFilePath.ensureTdfExtension(
      rawFileName.trim(),
    );
    final currentFileName = TdfFilePath.extractFileNameFromPath(
      previousConfig.localFilePath,
    );
    if (normalizedFileName == currentFileName) {
      return const ActionSucceeded();
    }

    final targetPath = _resolveChosenLocalFileName(
      previousConfig,
      normalizedFileName,
    );
    final candidateConfig = previousConfig.copyWith(localFilePath: targetPath);

    return _runGuardedAction(
      operation: SettingsBusyOperation.storageOperation,
      localizations: localizations,
      successMessage: localizations.localFileRenamedBanner,
      action: () async {
        await ref
            .read(webDavConfigProvider.notifier)
            .changeLocalFileLocation(candidateConfig);
        return true;
      },
      onSuccess: (banner) {
        UiTelemetry.logLocalTdfRenameConfirmed(
          fromFileName: currentFileName,
          toFileName: normalizedFileName,
        );
        state = state.copyWith(
          busyOperation: SettingsBusyOperation.idle,
          statusBanner: banner,
        );
      },
    );
  }

  /// Executes an auto-saved preference mutation via [persist] without acquiring a busy lock,
  /// surfacing localized danger banners on [WorkspaceException] failures.
  Future<ActionResult> savePreference(
    Future<void> Function(WebDavConfigNotifier notifier) persist, {
    Locale? locale,
  }) async {
    final workspaceId = _activeWorkspaceId;
    final localizations = _resolveLocalizations(locale);
    try {
      await persist(ref.read(webDavConfigProvider.notifier));
      if (!ref.mounted || _activeWorkspaceId != workspaceId) {
        return const ActionSucceeded();
      }
      if (state.statusBanner?.tone == SettingsBannerTone.danger) {
        state = state.copyWith(clearStatusBanner: true);
      }
      return const ActionSucceeded();
    } on Object catch (error) {
      final message = _formatSettingsError(error, localizations);
      if (!ref.mounted || _activeWorkspaceId != workspaceId) {
        return ActionPersistFailed(message: message);
      }
      showErrorBanner(message);
      return ActionPersistFailed(message: message);
    }
  }

  /// Validates and explicitly persists the transient WebDAV draft credentials and remote file path.
  Future<ActionResult> saveWebDavDraft({Locale? locale}) async {
    if (state.isBusy) {
      return const ActionSucceeded();
    }
    final localizations = _resolveLocalizations(locale);
    final validationFailure = _validateAndApplyWebDavDraft(localizations);
    if (validationFailure != null) {
      return validationFailure;
    }

    final previousConfig = readCurrentConfig(ref);
    final candidateConfig = _buildCandidateWebDavConfig(previousConfig);
    return _runGuardedAction(
      operation: SettingsBusyOperation.saveWebDav,
      localizations: localizations,
      successMessage: localizations.credentialsSavedBanner,
      action: () async {
        await ref
            .read(webDavConfigProvider.notifier)
            .updateConfig(candidateConfig);
        return true;
      },
      onSuccess: (banner) => _applyCommittedWebDavConfig(
        previousConfig: previousConfig,
        fallbackConfig: candidateConfig,
        banner: banner,
      ),
    );
  }

  /// Selects or creates a local `.tdf` file via [chosenFileName] or the native desktop file picker.
  Future<ActionResult> selectLocalFile({
    String? chosenFileName,
    Locale? locale,
  }) async {
    if (state.isBusy) {
      return const ActionSucceeded();
    }
    final localizations = _resolveLocalizations(locale);
    final supportsPicker = ref.read(supportsDirectoryPickerProvider);
    if (chosenFileName == null && !supportsPicker) {
      return _failLocalFileNameValidation(localizations);
    }
    if (chosenFileName != null &&
        !_isValidLocalSingleFileName(chosenFileName)) {
      return _failLocalFileNameValidation(localizations);
    }

    final previousConfig = readCurrentConfig(ref);
    return _runGuardedAction(
      operation: SettingsBusyOperation.storageOperation,
      localizations: localizations,
      successMessage: localizations.localFileSelectedBanner,
      action: () async {
        final targetPath = await _resolveSelectLocalTargetPath(
          previousConfig,
          chosenFileName,
        );
        if (targetPath == null) {
          return false;
        }
        UiTelemetry.logLocalTdfSelectConfirmed(
          TdfFilePath.extractFileNameFromPath(targetPath),
        );
        final candidateConfig = previousConfig.copyWith(
          localFilePath: targetPath,
        );
        await ref
            .read(taskNotifierProvider.notifier)
            .selectLocalFile(candidateConfig);
        return true;
      },
    );
  }

  /// Auto-saves persistence [mode], silently discarding unsaved WebDAV edits when switching to [StorageMode.local].
  Future<ActionResult> setStorageMode(StorageMode mode, {Locale? locale}) {
    if (mode == StorageMode.local) {
      if (state.isDirty) {
        discardWebDavDraft(reason: 'storage_mode_local');
      } else if (_hasValidationErrors) {
        state = state.copyWith(
          clearServerUrlError: true,
          clearUsernameError: true,
          clearPasswordError: true,
          clearFilePathError: true,
        );
      }
    }
    return savePreference(
      (notifier) => notifier.updateStorageMode(mode),
      locale: locale,
    );
  }

  /// Displays a danger status banner carrying [message].
  void showErrorBanner(String message) {
    state = state.copyWith(
      statusBanner: SettingsStatusBanner(
        tone: SettingsBannerTone.danger,
        message: message,
      ),
    );
  }

  /// Validates the WebDAV draft and runs `TaskNotifier.testConnectionAndSync` when WebDAV storage is enabled.
  Future<ActionResult> testConnectionAndSync({Locale? locale}) async {
    if (state.isBusy) {
      return const ActionSucceeded();
    }
    final localizations = _resolveLocalizations(locale);
    final previousConfig = readCurrentConfig(ref);
    if (previousConfig.storageMode == StorageMode.local) {
      return ActionValidationFailed(
        message: localizations.errorWebDavNotConfigured,
      );
    }

    final validationFailure = _validateAndApplyWebDavDraft(localizations);
    if (validationFailure != null) {
      return validationFailure;
    }

    final candidateConfig = _buildCandidateWebDavConfig(previousConfig);
    if (!candidateConfig.isWebDavConfigured) {
      final message = localizations.errorWebDavNotConfigured;
      showErrorBanner(message);
      return ActionValidationFailed(message: message);
    }

    return _runGuardedAction(
      operation: SettingsBusyOperation.testConnectionAndSync,
      localizations: localizations,
      successMessage: localizations.connectionSuccessBanner,
      action: () async {
        await ref
            .read(taskNotifierProvider.notifier)
            .testConnectionAndSync(candidateConfig);
        return true;
      },
      onSuccess: (banner) => _applyCommittedWebDavConfig(
        previousConfig: previousConfig,
        fallbackConfig: candidateConfig,
        banner: banner,
      ),
      onFailure: (banner) {
        final persisted = readCurrentConfig(ref);
        state = state.copyWith(
          isDirty: _computeIsDirty(
            persisted: persisted,
            serverUrl: state.serverUrl,
            username: state.username,
            password: state.password,
            filePath: state.filePath,
          ),
          busyOperation: SettingsBusyOperation.idle,
          statusBanner: banner,
        );
      },
    );
  }

  /// Updates transient WebDAV draft fields, clears edited field errors and banner, and recomputes dirty state.
  void updateWebDavDraft({
    String? serverUrl,
    String? username,
    String? password,
    String? filePath,
  }) {
    if (serverUrl == null &&
        username == null &&
        password == null &&
        filePath == null) {
      return;
    }
    final nextServerUrl = serverUrl ?? state.serverUrl;
    final nextUsername = username ?? state.username;
    final nextPassword = password ?? state.password;
    final nextFilePath = filePath ?? state.filePath;
    final persisted = readCurrentConfig(ref);
    final isDirty = _computeIsDirty(
      persisted: persisted,
      serverUrl: nextServerUrl,
      username: nextUsername,
      password: nextPassword,
      filePath: nextFilePath,
    );
    state = state.copyWith(
      serverUrl: nextServerUrl,
      username: nextUsername,
      password: nextPassword,
      filePath: nextFilePath,
      isDirty: isDirty,
      clearServerUrlError: serverUrl != null,
      clearUsernameError: username != null,
      clearPasswordError: password != null,
      clearFilePathError: filePath != null,
      clearStatusBanner: true,
    );
  }

  /// Wipes and re-initializes the local `.tdf` file with optional `.bak` backup creation.
  Future<ActionResult> wipeLocalFile({
    required bool createBackup,
    Locale? locale,
  }) async {
    if (state.isBusy) {
      return const ActionSucceeded();
    }
    final localizations = _resolveLocalizations(locale);
    final targetConfig = readCurrentConfig(ref);
    final resolvedPath = _createLocalRepository(targetConfig)
        .tryResolveFilePath();
    if (resolvedPath == null) {
      final message = localizations.errorInvalidLocalFilePath;
      showErrorBanner(message);
      return ActionValidationFailed(message: message);
    }

    final fileName = TdfFilePath.extractFileNameFromPath(
      targetConfig.localFilePath,
    );
    UiTelemetry.logWipeTdfConfirmed(
      targetName: 'local',
      fileName: fileName,
      createBackup: createBackup,
    );
    return _runGuardedAction(
      operation: SettingsBusyOperation.storageOperation,
      localizations: localizations,
      successMessage: localizations.localFileWipedBanner,
      action: () async {
        await ref
            .read(taskNotifierProvider.notifier)
            .wipeLocalFile(targetConfig, createBackup: createBackup);
        return true;
      },
    );
  }

  /// Wipes and re-initializes the remote WebDAV `.tdf` file with optional `.bak` backup creation.
  Future<ActionResult> wipeRemoteFile({
    required bool createBackup,
    Locale? locale,
  }) async {
    if (state.isBusy) {
      return const ActionSucceeded();
    }
    final localizations = _resolveLocalizations(locale);
    final targetConfig = readCurrentConfig(ref);
    if (!targetConfig.storageMode.usesWebDav ||
        !targetConfig.isWebDavConfigured) {
      final message = localizations.errorWebDavNotConfigured;
      showErrorBanner(message);
      return ActionValidationFailed(message: message);
    }

    final fileName = TdfFilePath.extractFileNameFromPath(targetConfig.filePath);
    UiTelemetry.logWipeTdfConfirmed(
      targetName: 'remote',
      fileName: fileName,
      createBackup: createBackup,
    );
    return _runGuardedAction(
      operation: SettingsBusyOperation.storageOperation,
      localizations: localizations,
      successMessage: localizations.remoteFileWipedBanner,
      action: () async {
        await ref
            .read(taskNotifierProvider.notifier)
            .wipeRemoteFile(targetConfig, createBackup: createBackup);
        return true;
      },
    );
  }

  /// Hydrates normalized committed WebDAV credentials after Save or Test & Sync and sets [banner].
  void _applyCommittedWebDavConfig({
    required WebDavConfig previousConfig,
    required WebDavConfig fallbackConfig,
    required SettingsStatusBanner banner,
  }) {
    final liveConfig = ref.read(webDavConfigProvider).asData?.value;
    final effectiveConfig = (liveConfig != null && liveConfig != previousConfig)
        ? liveConfig
        : fallbackConfig;
    state = state.copyWith(
      serverUrl: effectiveConfig.serverUrl,
      username: effectiveConfig.username,
      password: effectiveConfig.password,
      filePath: _normalizePersistedFilePath(effectiveConfig.filePath),
      isDirty: false,
      clearServerUrlError: true,
      clearUsernameError: true,
      clearPasswordError: true,
      clearFilePathError: true,
      busyOperation: SettingsBusyOperation.idle,
      statusBanner: banner,
    );
  }

  /// Builds a normalized [WebDavConfig] combining [baseConfig] with the current WebDAV draft fields.
  WebDavConfig _buildCandidateWebDavConfig(WebDavConfig baseConfig) {
    final trimmedFilePath = state.filePath.trim();
    return baseConfig.copyWith(
      serverUrl: state.serverUrl.trim(),
      username: state.username.trim(),
      password: state.password,
      filePath: trimmedFilePath.isEmpty
          ? WebDavConfig.defaultFileName
          : trimmedFilePath,
    );
  }

  /// Returns `true` when any draft WebDAV field differs from [persisted].
  bool _computeIsDirty({
    required WebDavConfig persisted,
    required String serverUrl,
    required String username,
    required String password,
    required String filePath,
  }) {
    final persistedFilePath = _normalizePersistedFilePath(persisted.filePath);
    return serverUrl != persisted.serverUrl ||
        username != persisted.username ||
        password != persisted.password ||
        filePath != persistedFilePath;
  }

  /// Constructs a [LocalFileRepository] scoped to [config] for storage dialog path resolution.
  LocalFileRepository _createLocalRepository(WebDavConfig config) {
    return LocalFileRepository(
      config: config,
      baseDirectoryPath: ref.read(localStorageDirectoryPathProvider),
      buildProfile: ref.read(appBuildProfileProvider),
    );
  }

  /// Sets a danger status banner for an invalid local `.tdf` filename and returns a validation failure.
  ActionValidationFailed _failLocalFileNameValidation(
    AppLocalizations localizations,
  ) {
    final message = localizations.localFileNameErrorInvalid;
    showErrorBanner(message);
    return ActionValidationFailed(
      message: message,
      fieldErrors: <String, String>{'localFileName': message},
    );
  }

  /// Updates [SettingsDraftState.resolvedLocalPathPreview] when the local storage binding changes.
  void _handleResolvedLocalPathChanged(String? previous, String? next) {
    if (state.resolvedLocalPathPreview == next) {
      return;
    }
    state = state.copyWith(
      resolvedLocalPathPreview: next,
      clearResolvedLocalPathPreview: next == null,
    );
  }

  /// Silently discards dirty WebDAV edits or stale validation errors when navigating away from Settings (`U-UX-006`).
  void _handleShellViewChanged(ShellView? previous, ShellView next) {
    if (previous != ShellView.settings || next == ShellView.settings) {
      return;
    }
    if (state.isDirty) {
      discardWebDavDraft(reason: 'navigation');
      return;
    }
    if (_hasValidationErrors) {
      state = state.copyWith(
        clearServerUrlError: true,
        clearUsernameError: true,
        clearPasswordError: true,
        clearFilePathError: true,
      );
    }
  }

  /// Hydrates clean WebDAV draft fields on config updates and discards dirty drafts when switching to local mode.
  void _handleWebDavConfigSliceChanged(
    _WebDavConfigSlice? previous,
    _WebDavConfigSlice? next,
  ) {
    if (next == null) {
      return;
    }
    final liveWorkspaceId = ref.read(activeWorkspaceProvider).asData?.value.id;
    if (liveWorkspaceId != null &&
        _activeWorkspaceId != null &&
        liveWorkspaceId != _activeWorkspaceId) {
      _handleWorkspaceIdChanged(_activeWorkspaceId, liveWorkspaceId);
      return;
    }
    final switchedToLocal =
        next.storageMode == StorageMode.local &&
        previous?.storageMode != StorageMode.local;
    if (switchedToLocal && state.isDirty) {
      UiTelemetry.logSettingsWebDavDraftDiscarded('storage_mode_local');
      state = state.copyWith(
        serverUrl: next.serverUrl,
        username: next.username,
        password: next.password,
        filePath: _normalizePersistedFilePath(next.filePath),
        isDirty: false,
        clearServerUrlError: true,
        clearUsernameError: true,
        clearPasswordError: true,
        clearFilePathError: true,
        clearStatusBanner: true,
      );
      return;
    }
    if (switchedToLocal && _hasValidationErrors) {
      state = state.copyWith(
        serverUrl: next.serverUrl,
        username: next.username,
        password: next.password,
        filePath: _normalizePersistedFilePath(next.filePath),
        clearServerUrlError: true,
        clearUsernameError: true,
        clearPasswordError: true,
        clearFilePathError: true,
      );
      return;
    }
    if (state.isDirty) {
      return;
    }
    final normalizedFilePath = _normalizePersistedFilePath(next.filePath);
    if (state.serverUrl == next.serverUrl &&
        state.username == next.username &&
        state.password == next.password &&
        state.filePath == normalizedFilePath) {
      return;
    }
    state = state.copyWith(
      serverUrl: next.serverUrl,
      username: next.username,
      password: next.password,
      filePath: normalizedFilePath,
    );
  }

  /// Resets transient WebDAV draft, validation, busy, and banner state on actual workspace switches.
  void _handleWorkspaceIdChanged(
    String? previousWorkspaceId,
    String? nextWorkspaceId,
  ) {
    if (nextWorkspaceId == null) {
      return;
    }
    final switchedWorkspace =
        _activeWorkspaceId != null && _activeWorkspaceId != nextWorkspaceId;
    _activeWorkspaceId = nextWorkspaceId;
    if (!switchedWorkspace) {
      return;
    }
    if (state.isDirty) {
      UiTelemetry.logSettingsWebDavDraftDiscarded('workspace_switch');
    }
    final nextConfig =
        ref.read(activeWorkspaceProvider).asData?.value.config ??
        readCurrentConfig(ref);
    final nextLocalPathPreview = ref
        .read(localFileRepositoryProvider)
        .tryResolveFilePath();
    state = SettingsDraftState(
      serverUrl: nextConfig.serverUrl,
      username: nextConfig.username,
      password: nextConfig.password,
      filePath: _normalizePersistedFilePath(nextConfig.filePath),
      resolvedLocalPathPreview: nextLocalPathPreview,
    );
  }

  /// Combines [chosenFileName] with the resolved directory of [config] when a base or explicit directory applies.
  String _resolveChosenLocalFileName(
    WebDavConfig config,
    String chosenFileName,
  ) {
    final baseDirectoryPath = ref.read(localStorageDirectoryPathProvider);
    final currentDirectory = _createLocalRepository(config)
        .tryResolveDirectoryPath();
    final hasDirectory =
        _pathSeparatorPattern.hasMatch(config.localFilePath) ||
        baseDirectoryPath != null;
    return (hasDirectory && currentDirectory != null)
        ? LocalFileRepository.combineDirectoryAndFileName(
            currentDirectory,
            chosenFileName,
          )
        : chosenFileName;
  }

  /// Resolves localized strings for [locale] or falls back to [appLocaleProvider].
  AppLocalizations _resolveLocalizations(Locale? locale) =>
      lookupAppLocalizations(locale ?? ref.read(appLocaleProvider));

  /// Resolves the target file path for [selectLocalFile] from [chosenFileName] or the native desktop file picker.
  Future<String?> _resolveSelectLocalTargetPath(
    WebDavConfig baseConfig,
    String? chosenFileName,
  ) async {
    if (chosenFileName != null) {
      final normalizedName = TdfFilePath.ensureTdfExtension(
        chosenFileName.trim(),
      );
      return _resolveChosenLocalFileName(baseConfig, normalizedName);
    }
    final repository = _createLocalRepository(baseConfig);
    final pickedPath = await ref.read(filePickerProvider)(
      initialDirectory: repository.tryResolveDirectoryPath(),
      currentFileName: repository.extractFileName(),
    );
    if (pickedPath == null || pickedPath.trim().isEmpty) {
      return null;
    }
    return pickedPath.trim();
  }

  /// Executes a blocking WebDAV or storage [action] under [operation] with liveness checks and banner reporting.
  Future<ActionResult> _runGuardedAction({
    required SettingsBusyOperation operation,
    required AppLocalizations localizations,
    required String successMessage,
    required Future<bool> Function() action,
    void Function(SettingsStatusBanner successBanner)? onSuccess,
    void Function(SettingsStatusBanner failureBanner)? onFailure,
  }) async {
    final workspaceId = _activeWorkspaceId;
    state = state.copyWith(busyOperation: operation, clearStatusBanner: true);
    try {
      final completed = await action();
      if (!ref.mounted || _activeWorkspaceId != workspaceId) {
        return const ActionSucceeded();
      }
      if (!completed) {
        state = state.copyWith(busyOperation: SettingsBusyOperation.idle);
        return const ActionSucceeded();
      }
      final banner = SettingsStatusBanner(
        tone: SettingsBannerTone.success,
        message: successMessage,
      );
      if (onSuccess != null) {
        onSuccess(banner);
      } else {
        state = state.copyWith(
          busyOperation: SettingsBusyOperation.idle,
          statusBanner: banner,
        );
      }
      return ActionSucceeded(noticeMessage: successMessage);
    } on Object catch (error) {
      final message = _formatSettingsError(error, localizations);
      if (!ref.mounted || _activeWorkspaceId != workspaceId) {
        return ActionPersistFailed(message: message);
      }
      final banner = SettingsStatusBanner(
        tone: SettingsBannerTone.danger,
        message: message,
      );
      if (onFailure != null) {
        onFailure(banner);
      } else {
        state = state.copyWith(
          busyOperation: SettingsBusyOperation.idle,
          statusBanner: banner,
        );
      }
      return ActionPersistFailed(message: message);
    }
  }

  /// Validates the current WebDAV draft, updates field errors and top danger banner on failure, and returns `null` when valid.
  ActionValidationFailed? _validateAndApplyWebDavDraft(
    AppLocalizations localizations,
  ) {
    final serverUrlError = _validateServerUrl(state.serverUrl, localizations);
    final usernameError = state.username.trim().isEmpty
        ? localizations.usernameErrorEmpty
        : null;
    final passwordError = state.password.isEmpty
        ? localizations.passwordErrorEmpty
        : null;
    final filePathError = _validateRemoteFilePath(
      state.filePath,
      localizations,
    );

    final fieldErrors = <String, String>{
      'serverUrl': ?serverUrlError,
      'username': ?usernameError,
      'password': ?passwordError,
      'filePath': ?filePathError,
    };
    final primaryMessage =
        serverUrlError ?? usernameError ?? passwordError ?? filePathError;
    if (primaryMessage == null) {
      if (_hasValidationErrors) {
        state = state.copyWith(
          clearServerUrlError: true,
          clearUsernameError: true,
          clearPasswordError: true,
          clearFilePathError: true,
        );
      }
      return null;
    }

    state = state.copyWith(
      serverUrlError: serverUrlError,
      clearServerUrlError: serverUrlError == null,
      usernameError: usernameError,
      clearUsernameError: usernameError == null,
      passwordError: passwordError,
      clearPasswordError: passwordError == null,
      filePathError: filePathError,
      clearFilePathError: filePathError == null,
      statusBanner: SettingsStatusBanner(
        tone: SettingsBannerTone.danger,
        message: primaryMessage,
      ),
    );
    return ActionValidationFailed(
      message: primaryMessage,
      fieldErrors: fieldErrors,
    );
  }
}

/// Immutable transient WebDAV draft, validation, banner, busy, and local path preview state for Settings.
@immutable
class SettingsDraftState {
  /// Creates a [SettingsDraftState].
  const SettingsDraftState({
    this.serverUrl = '',
    this.username = '',
    this.password = '',
    this.filePath = WebDavConfig.defaultFileName,
    this.isDirty = false,
    this.serverUrlError,
    this.usernameError,
    this.passwordError,
    this.filePathError,
    this.statusBanner,
    this.busyOperation = SettingsBusyOperation.idle,
    this.resolvedLocalPathPreview,
  });

  /// Blocking asynchronous operation currently running in [SettingsDraftNotifier].
  final SettingsBusyOperation busyOperation;

  /// Transient draft value of the remote WebDAV `.tdf` file path field.
  final String filePath;

  /// Inline validation error for the remote WebDAV `.tdf` file path field, if any.
  final String? filePathError;

  /// Whether the WebDAV draft form has uncommitted edits compared to persisted configuration.
  final bool isDirty;

  /// Transient draft value of the WebDAV password field.
  final String password;

  /// Inline validation error for the WebDAV password field, if any.
  final String? passwordError;

  /// Cached resolved local `.tdf` filesystem path preview, or `null` when invalid.
  final String? resolvedLocalPathPreview;

  /// Transient draft value of the WebDAV server URL field.
  final String serverUrl;

  /// Inline validation error for the WebDAV server URL field, if any.
  final String? serverUrlError;

  /// Active top status banner in Settings, if any.
  final SettingsStatusBanner? statusBanner;

  /// Transient draft value of the WebDAV username field.
  final String username;

  /// Inline validation error for the WebDAV username field, if any.
  final String? usernameError;

  /// Live resolved WebDAV endpoint URI preview computed purely from draft inputs without disk or repository allocation.
  String get endpointPreview =>
      WebDavConfig(
        serverUrl: serverUrl,
        username: username,
        filePath: filePath,
      ).resolveEndpointUri()?.toString() ??
      '';

  /// Whether a blocking WebDAV save, test/sync, or storage operation is in flight.
  bool get isBusy => busyOperation != SettingsBusyOperation.idle;

  /// Whether explicit WebDAV credential saving is currently in flight.
  bool get isSavingWebDav => busyOperation == SettingsBusyOperation.saveWebDav;

  /// Whether a local or remote `.tdf` file move, rename, select, or wipe is currently in flight.
  bool get isStorageOperationBusy =>
      busyOperation == SettingsBusyOperation.storageOperation;

  /// Whether WebDAV connection testing and synchronization is currently in flight.
  bool get isTestingConnection =>
      busyOperation == SettingsBusyOperation.testConnectionAndSync;

  /// Returns a copy of this [SettingsDraftState] with selectively updated fields.
  SettingsDraftState copyWith({
    String? serverUrl,
    String? username,
    String? password,
    String? filePath,
    bool? isDirty,
    String? serverUrlError,
    bool clearServerUrlError = false,
    String? usernameError,
    bool clearUsernameError = false,
    String? passwordError,
    bool clearPasswordError = false,
    String? filePathError,
    bool clearFilePathError = false,
    SettingsStatusBanner? statusBanner,
    bool clearStatusBanner = false,
    SettingsBusyOperation? busyOperation,
    String? resolvedLocalPathPreview,
    bool clearResolvedLocalPathPreview = false,
  }) {
    return SettingsDraftState(
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      filePath: filePath ?? this.filePath,
      isDirty: isDirty ?? this.isDirty,
      serverUrlError: clearServerUrlError
          ? null
          : (serverUrlError ?? this.serverUrlError),
      usernameError: clearUsernameError
          ? null
          : (usernameError ?? this.usernameError),
      passwordError: clearPasswordError
          ? null
          : (passwordError ?? this.passwordError),
      filePathError: clearFilePathError
          ? null
          : (filePathError ?? this.filePathError),
      statusBanner: clearStatusBanner
          ? null
          : (statusBanner ?? this.statusBanner),
      busyOperation: busyOperation ?? this.busyOperation,
      resolvedLocalPathPreview: clearResolvedLocalPathPreview
          ? null
          : (resolvedLocalPathPreview ?? this.resolvedLocalPathPreview),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SettingsDraftState &&
        other.serverUrl == serverUrl &&
        other.username == username &&
        other.password == password &&
        other.filePath == filePath &&
        other.isDirty == isDirty &&
        other.serverUrlError == serverUrlError &&
        other.usernameError == usernameError &&
        other.passwordError == passwordError &&
        other.filePathError == filePathError &&
        other.statusBanner == statusBanner &&
        other.busyOperation == busyOperation &&
        other.resolvedLocalPathPreview == resolvedLocalPathPreview;
  }

  @override
  int get hashCode => Object.hash(
    serverUrl,
    username,
    password,
    filePath,
    isDirty,
    serverUrlError,
    usernameError,
    passwordError,
    filePathError,
    statusBanner,
    busyOperation,
    resolvedLocalPathPreview,
  );

  @override
  String toString() =>
      'SettingsDraftState(serverUrl: $serverUrl, '
      'username: $username, '
      'password: ${password.isEmpty ? "" : "[REDACTED]"}, '
      'filePath: $filePath, '
      'isDirty: $isDirty, '
      'busyOperation: ${busyOperation.name}, '
      'resolvedLocalPathPreview: $resolvedLocalPathPreview)';
}

/// Immutable top status banner displayed inside the Settings view.
@immutable
class SettingsStatusBanner {
  /// Creates a [SettingsStatusBanner].
  const SettingsStatusBanner({required this.tone, required this.message});

  /// Sanitized localized message displayed inside the status banner.
  final String message;

  /// Semantic visual tone of the status banner.
  final SettingsBannerTone tone;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SettingsStatusBanner &&
        other.tone == tone &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hash(tone, message);
}

/// Narrow persisted WebDAV slice watched by [SettingsDraftNotifier] for hydration and local-mode discard.
typedef _WebDavConfigSlice = ({
  String filePath,
  String password,
  String serverUrl,
  StorageMode storageMode,
  String username,
});

/// Extracts the raw unnormalized path portion of [trimmedUrl] after the authority segment.
String _extractRawUrlPath(String trimmedUrl) {
  final schemeSeparatorIndex = trimmedUrl.indexOf('://');
  if (schemeSeparatorIndex < 0) {
    return '';
  }
  final pathStart = trimmedUrl.indexOf('/', schemeSeparatorIndex + 3);
  if (pathStart < 0) {
    return '';
  }
  var pathEnd = trimmedUrl.length;
  for (var i = pathStart; i < trimmedUrl.length; i++) {
    final codeUnit = trimmedUrl.codeUnitAt(i);
    if (codeUnit == 0x3F || codeUnit == 0x23) {
      pathEnd = i;
      break;
    }
  }
  return trimmedUrl.substring(pathStart, pathEnd);
}

/// Formats a settings storage or workspace [error] into a sanitized localized status message.
String _formatSettingsError(Object error, AppLocalizations localizations) {
  return switch (error) {
    final WorkspaceException workspaceError =>
      localizations.localizeWorkspaceError(workspaceError),
    final StorageFileReadException fileReadError => AppLogger.sanitize(
      localizations.formatStorageFileReadMessage(fileReadError.report),
    ),
    final LocalFileException localFileError => AppLogger.sanitize(
      localFileError.message,
    ),
    final WebDavException webDavError => AppLogger.sanitize(
      webDavError.toString(),
    ),
    _ => AppLogger.sanitize(error.toString()),
  };
}

/// Returns `true` when [value] contains ASCII control characters (`0x00..0x1F`) or `DEL` (`0x7F`).
bool _hasControlCharacters(String value) {
  for (var i = 0; i < value.length; i++) {
    final codeUnit = value.codeUnitAt(i);
    if (codeUnit < 0x20 || codeUnit == 0x7F) {
      return true;
    }
  }
  return false;
}

/// Returns `true` when the authority segment of [trimmedUrl] contains `@` (embedded userinfo).
bool _hasEmbeddedUserInfo(String trimmedUrl) {
  final schemeSeparatorIndex = trimmedUrl.indexOf('://');
  if (schemeSeparatorIndex < 0) {
    return false;
  }
  final authorityStart = schemeSeparatorIndex + 3;
  var authorityEnd = trimmedUrl.length;
  for (var i = authorityStart; i < trimmedUrl.length; i++) {
    final codeUnit = trimmedUrl.codeUnitAt(i);
    if (codeUnit == 0x2F || codeUnit == 0x3F || codeUnit == 0x23) {
      authorityEnd = i;
      break;
    }
  }
  final atIndex = trimmedUrl.indexOf('@', authorityStart);
  return atIndex >= authorityStart && atIndex < authorityEnd;
}

/// Returns `true` when [segments] contains `.` or `..` path traversal elements.
bool _hasInvalidPathSegments(Iterable<String> segments) {
  for (final segment in segments) {
    if (segment == '.' || segment == '..') {
      return true;
    }
  }
  return false;
}

/// Returns `true` when [rawName] is a safe single local `.tdf` filename without separators, `..`, or control characters.
bool _isValidLocalSingleFileName(String rawName) {
  if (_hasControlCharacters(rawName)) {
    return false;
  }
  final trimmed = rawName.trim();
  return TdfFilePath.isValidSingleFileName(trimmed) && !trimmed.contains('..');
}

/// Returns [rawFilePath] or [WebDavConfig.defaultFileName] when empty.
String _normalizePersistedFilePath(String rawFilePath) =>
    rawFilePath.isEmpty ? WebDavConfig.defaultFileName : rawFilePath;

/// Validates a draft remote WebDAV [rawFilePath], returning a localized error or `null` when valid.
String? _validateRemoteFilePath(
  String rawFilePath,
  AppLocalizations localizations,
) {
  if (_hasControlCharacters(rawFilePath)) {
    return localizations.webDavPathInvalidError;
  }
  final trimmed = rawFilePath.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  if (trimmed.contains(r'\') ||
      trimmed.contains('..') ||
      trimmed.contains('?') ||
      trimmed.contains('#')) {
    return localizations.webDavPathInvalidError;
  }
  final segments = trimmed.split('/');
  if (_hasInvalidPathSegments(segments)) {
    return localizations.webDavPathInvalidError;
  }
  final hasNonEmptySegment = segments.any((segment) => segment.isNotEmpty);
  if (!hasNonEmptySegment) {
    return localizations.webDavPathInvalidError;
  }
  return null;
}

/// Validates a draft WebDAV [rawServerUrl], returning a localized error or `null` when valid.
String? _validateServerUrl(
  String rawServerUrl,
  AppLocalizations localizations,
) {
  if (_hasControlCharacters(rawServerUrl)) {
    return localizations.errorInvalidServerUrl;
  }
  final trimmed = rawServerUrl.trim();
  if (trimmed.isEmpty) {
    return localizations.serverUrlErrorEmpty;
  }
  if (trimmed.contains(r'\')) {
    return localizations.errorInvalidServerUrl;
  }
  final lower = trimmed.toLowerCase();
  if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
    return localizations.errorInvalidServerUrl;
  }
  if (_hasEmbeddedUserInfo(trimmed)) {
    return localizations.webDavUrlUserinfoError;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return localizations.errorInvalidServerUrl;
  }
  if (uri.userInfo.isNotEmpty) {
    return localizations.webDavUrlUserinfoError;
  }
  final rawPath = _extractRawUrlPath(trimmed);
  if (uri.host.isEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      _hasInvalidPathSegments(rawPath.split('/')) ||
      _hasInvalidPathSegments(uri.pathSegments)) {
    return localizations.errorInvalidServerUrl;
  }
  return null;
}
