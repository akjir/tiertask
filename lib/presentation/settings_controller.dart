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
import '../providers/config_providers.dart';
import '../providers/sync_providers.dart';
import '../providers/task_providers.dart';
import '../providers/workspace_providers.dart';
import '../repositories/local_file_repository.dart';
import '../repositories/webdav_repository.dart';
import '../services/app_logger.dart';
import 'app_shell_controller.dart';
import 'log_viewer_controller.dart';
import 'settings_storage_controller.dart';
import 'shell_models.dart';
import 'ui_telemetry.dart';

/// Provides the model-free Settings presentation state and mutation controller (`U-UX-006`).
final settingsControllerProvider =
    NotifierProvider<SettingsController, SettingsViewModel>(
      SettingsController.new,
    );

/// Immutable top status banner displayed inside the Settings view.
@immutable
class SettingsStatusBannerViewModel {
  /// Creates a [SettingsStatusBannerViewModel].
  const SettingsStatusBannerViewModel({
    required this.tone,
    required this.message,
  });

  /// Sanitized localized message displayed inside the status banner.
  final String message;

  /// Semantic visual tone of the status banner.
  final BannerTone tone;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SettingsStatusBannerViewModel &&
        other.tone == tone &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hash(tone, message);
}

/// Model-free Settings presentation controller enforcing dual persistence (`U-UX-006`),
/// explicit WebDAV validation, silent draft discard, and capability-gated storage operations.
class SettingsController extends Notifier<SettingsViewModel> {
  /// Cached immutable list of all 37 selectable UTC offset options.
  static final List<UtcOffsetOptionViewModel> _supportedUtcOffsets =
      List<UtcOffsetOptionViewModel>.unmodifiable(<UtcOffsetOptionViewModel>[
        for (final offsetMinutes in WebDavConfig.supportedUtcOffsetMinutes)
          UtcOffsetOptionViewModel(
            offsetMinutes: offsetMinutes,
            label: WebDavConfig.formatUtcOffset(offsetMinutes),
          ),
      ]);

  String _activeLogFileName = '';
  String? _activeWorkspaceId;
  String _draftFilePath = WebDavConfig.defaultFileName;
  String _draftPassword = '';
  String _draftServerUrl = '';
  String _draftUsername = '';
  String? _filePathError;
  bool _isBusy = false;
  bool _isWebDavDirty = false;
  String? _passwordError;
  WebDavConfig _persistedConfig = const WebDavConfig();
  String? _serverUrlError;
  SettingsStatusBannerViewModel? _statusBanner;
  bool _supportsNativeDirectoryPicker = false;
  String? _usernameError;
  String _workspaceName = AppWorkspace.defaultName;

  /// Whether any inline WebDAV validation error is currently set.
  bool get _hasValidationErrors =>
      _serverUrlError != null ||
      _usernameError != null ||
      _passwordError != null ||
      _filePathError != null;

  @override
  SettingsViewModel build() {
    final configAsync = ref.watch(webDavConfigProvider);
    final workspaceAsync = ref.watch(activeWorkspaceProvider);
    final supportsPicker = ref.watch(supportsNativeDirectoryPickerProvider);
    final activeLogFileName = ref.watch(activeLogFileNameProvider);

    ref.listen<ShellView>(
      appShellControllerProvider.select((shell) => shell.view),
      _handleShellViewChanged,
    );

    final workspace = workspaceAsync.asData?.value;
    final persistedConfig =
        configAsync.asData?.value ?? workspace?.config ?? const WebDavConfig();
    _syncWorkspaceAndDraft(
      workspaceId: workspace?.id,
      persistedConfig: persistedConfig,
    );

    _persistedConfig = persistedConfig;
    _workspaceName = workspace?.name ?? AppWorkspace.defaultName;
    _supportsNativeDirectoryPicker = supportsPicker;
    _activeLogFileName = activeLogFileName;
    return _buildCurrentViewModel();
  }

  /// Discards unsaved WebDAV edits, resets draft fields to persisted config, and clears validation errors.
  void discardWebDavDraft({String reason = 'manual'}) {
    if (_isWebDavDirty) {
      UiTelemetry.logSettingsWebDavDraftDiscarded(reason);
    }
    _isWebDavDirty = false;
    _hydrateDraftFromConfig(_persistedConfig);
    _clearValidationErrors();
    _statusBanner = null;
    state = _buildCurrentViewModel();
  }

  /// Dismisses the currently displayed settings status banner.
  void dismissStatusBanner() {
    if (_statusBanner == null) {
      return;
    }
    _statusBanner = null;
    state = _buildCurrentViewModel();
  }

  /// Lists sorted `.tdf` filenames discovered in the active local storage directory.
  List<String> listLocalTdfFileNames() =>
      ref.read(settingsStorageControllerProvider).listLocalTdfFileNames();

  /// Moves the active local `.tdf` file to a user-picked directory when native directory picking is supported.
  Future<ActionResult> moveLocalDirectory({Locale? locale}) async {
    if (_isBusy) {
      return const ActionSucceeded();
    }
    final localizations = _resolveLocalizations(locale);
    if (!_supportsNativeDirectoryPicker) {
      return ActionValidationFailed(
        message: localizations.settingsMoveDesktopOnlyTooltip,
      );
    }

    final previousConfig = _persistedConfig;
    WebDavConfig? movedConfig;
    return _runGuardedAction(
      localizations: localizations,
      successMessage: localizations.localDirectoryMovedBanner,
      action: () async {
        final targetPath = await ref
            .read(settingsStorageControllerProvider)
            .pickLocalDirectory(previousConfig);
        if (targetPath == null || targetPath.trim().isEmpty) {
          return false;
        }
        final candidateConfig = previousConfig.copyWith(
          localFilePath: targetPath.trim(),
        );
        movedConfig = candidateConfig;
        await ref
            .read(webDavConfigProvider.notifier)
            .changeLocalFileLocation(candidateConfig);
        return true;
      },
      onSuccess: () {
        if (movedConfig case final nextConfig?) {
          _applyCommittedConfig(
            previousConfig: previousConfig,
            fallbackConfig: nextConfig,
            clearWebDavDirty: false,
          );
        }
      },
    );
  }

  /// Validates [rawFileName] and renames the local `.tdf` file within its current directory.
  Future<ActionResult> renameLocalFile(
    String rawFileName, {
    Locale? locale,
  }) async {
    if (_isBusy) {
      return const ActionSucceeded();
    }
    final localizations = _resolveLocalizations(locale);
    if (!_isValidLocalSingleFileName(rawFileName)) {
      return _failLocalFileNameValidation(localizations);
    }

    final normalizedFileName = TdfFilePath.ensureTdfExtension(
      rawFileName.trim(),
    );
    final currentFileName = TdfFilePath.extractFileNameFromPath(
      _persistedConfig.localFilePath,
    );
    if (normalizedFileName == currentFileName) {
      return const ActionSucceeded();
    }

    final previousConfig = _persistedConfig;
    final targetPath = ref
        .read(settingsStorageControllerProvider)
        .resolveChosenLocalFileName(previousConfig, normalizedFileName);
    final candidateConfig = previousConfig.copyWith(localFilePath: targetPath);

    return _runGuardedAction(
      localizations: localizations,
      successMessage: localizations.localFileRenamedBanner,
      action: () async {
        await ref
            .read(webDavConfigProvider.notifier)
            .changeLocalFileLocation(candidateConfig);
        return true;
      },
      onSuccess: () {
        UiTelemetry.logLocalTdfRenameConfirmed(
          fromFileName: currentFileName,
          toFileName: normalizedFileName,
        );
        _applyCommittedConfig(
          previousConfig: previousConfig,
          fallbackConfig: candidateConfig,
          clearWebDavDirty: false,
        );
      },
    );
  }

  /// Validates and explicitly persists the transient WebDAV draft credentials and remote file path.
  Future<ActionResult> saveWebDavDraft({Locale? locale}) async {
    if (_isBusy) {
      return const ActionSucceeded();
    }
    final localizations = _resolveLocalizations(locale);
    final validationFailure = _validateAndApplyWebDavDraft(localizations);
    if (validationFailure != null) {
      return validationFailure;
    }

    final previousConfig = _persistedConfig;
    final candidateConfig = _buildCandidateWebDavConfig(previousConfig);
    return _runGuardedAction(
      localizations: localizations,
      successMessage: localizations.credentialsSavedBanner,
      action: () async {
        await ref
            .read(webDavConfigProvider.notifier)
            .updateConfig(candidateConfig);
        return true;
      },
      onSuccess: () {
        _applyCommittedConfig(
          previousConfig: previousConfig,
          fallbackConfig: candidateConfig,
          clearWebDavDirty: true,
        );
      },
    );
  }

  /// Selects or creates a local `.tdf` file via [chosenFileName] or the native desktop file picker.
  Future<ActionResult> selectLocalFile({
    String? chosenFileName,
    Locale? locale,
  }) async {
    if (_isBusy) {
      return const ActionSucceeded();
    }
    final localizations = _resolveLocalizations(locale);
    if (chosenFileName == null && !_supportsNativeDirectoryPicker) {
      return _failLocalFileNameValidation(localizations);
    }
    if (chosenFileName != null &&
        !_isValidLocalSingleFileName(chosenFileName)) {
      return _failLocalFileNameValidation(localizations);
    }

    final previousConfig = _persistedConfig;
    WebDavConfig? selectedConfig;
    return _runGuardedAction(
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
        selectedConfig = candidateConfig;
        await ref
            .read(taskNotifierProvider.notifier)
            .selectLocalFile(candidateConfig);
        return true;
      },
      onSuccess: () {
        if (selectedConfig case final nextConfig?) {
          _applyCommittedConfig(
            previousConfig: previousConfig,
            fallbackConfig: nextConfig,
            clearWebDavDirty: false,
          );
        }
      },
    );
  }

  /// Auto-saves whether opt-in diagnostic logging is enabled.
  Future<ActionResult> setDiagnosticsEnabled(bool enabled, {Locale? locale}) =>
      _savePreference(
        nextConfig: _persistedConfig.copyWith(diagnosticsEnabled: enabled),
        locale: locale,
      );

  /// Auto-saves the per-workspace deadline lead window.
  Future<ActionResult> setDueLeadWindow(
    ShellDueLeadOption value, {
    Locale? locale,
  }) => _savePreference(
    nextConfig: _persistedConfig.copyWith(
      dueLeadWindow: _toDueLeadWindow(value),
    ),
    locale: locale,
  );

  /// Auto-saves the display language preference.
  Future<ActionResult> setLanguage(
    ShellLanguageOption value, {
    Locale? locale,
  }) => _savePreference(
    nextConfig: _persistedConfig.copyWith(language: _toAppLanguage(value)),
    locale: locale,
  );

  /// Auto-saves whether external local `.tdf` file watching is enabled.
  Future<ActionResult> setLocalWatchEnabled(bool enabled, {Locale? locale}) =>
      _savePreference(
        nextConfig: _persistedConfig.copyWith(localWatchEnabled: enabled),
        locale: locale,
      );

  /// Auto-saves whether foreground location determination is enabled.
  Future<ActionResult> setLocationEnabled(bool enabled, {Locale? locale}) =>
      _savePreference(
        nextConfig: _persistedConfig.copyWith(locationEnabled: enabled),
        locale: locale,
      );

  /// Auto-saves the minimum diagnostic log severity threshold.
  Future<ActionResult> setLogLevel(
    DiagnosticLogLevel level, {
    Locale? locale,
  }) => _savePreference(
    nextConfig: _persistedConfig.copyWith(logLevel: level.toLogLevel()),
    locale: locale,
  );

  /// Auto-saves the diagnostic log storage target (`local`, `webdav`, or `both`).
  Future<ActionResult> setLogStorageMode(
    ShellStorageMode mode, {
    Locale? locale,
  }) => _savePreference(
    nextConfig: _persistedConfig.copyWith(logStorageMode: _toStorageMode(mode)),
    locale: locale,
  );

  /// Auto-saves the manual UTC offset in minutes (clamped to `[-720, 840]`).
  Future<ActionResult> setManualTimeZoneOffsetMinutes(
    int offsetMinutes, {
    Locale? locale,
  }) => _savePreference(
    nextConfig: _persistedConfig.copyWith(
      manualTimeZoneOffsetMinutes: offsetMinutes,
    ),
    locale: locale,
  );

  /// Auto-saves the persistence [mode], immediately discarding unsaved WebDAV edits and errors when switching to [ShellStorageMode.local].
  Future<ActionResult> setStorageMode(ShellStorageMode mode, {Locale? locale}) {
    if (_isBusy) {
      return Future<ActionResult>.value(const ActionSucceeded());
    }
    if (mode == ShellStorageMode.local) {
      if (_isWebDavDirty) {
        UiTelemetry.logSettingsWebDavDraftDiscarded('storage_mode_local');
      }
      _isWebDavDirty = false;
      _hydrateDraftFromConfig(_persistedConfig);
      _clearValidationErrors();
    }
    return _savePreference(
      nextConfig: _persistedConfig.copyWith(storageMode: _toStorageMode(mode)),
      locale: locale,
    );
  }

  /// Auto-saves the color brightness mode (`system`, `light`, or `dark`).
  Future<ActionResult> setThemeMode(ShellThemeMode value, {Locale? locale}) =>
      _savePreference(
        nextConfig: _persistedConfig.copyWith(
          themeMode: _toAppThemeMode(value),
        ),
        locale: locale,
      );

  /// Auto-saves the design-system color palette (`calm` or `plum_umber`).
  Future<ActionResult> setThemePalette(
    AppThemePresetKey value, {
    Locale? locale,
  }) => _savePreference(
    nextConfig: _persistedConfig.copyWith(
      themePalette: _toAppThemePalette(value),
    ),
    locale: locale,
  );

  /// Auto-saves the time zone resolution mode (`automatic` or `manual`).
  Future<ActionResult> setTimeZoneMode(
    ShellTimeZoneMode value, {
    Locale? locale,
  }) => _savePreference(
    nextConfig: _persistedConfig.copyWith(
      timeZoneMode: _toAppTimeZoneMode(value),
    ),
    locale: locale,
  );

  /// Validates the WebDAV draft and executes `TaskNotifier.testConnectionAndSync` when WebDAV storage is enabled.
  Future<ActionResult> testConnectionAndSync({Locale? locale}) async {
    if (_isBusy) {
      return const ActionSucceeded();
    }
    final localizations = _resolveLocalizations(locale);
    if (_persistedConfig.storageMode == StorageMode.local) {
      return ActionValidationFailed(
        message: localizations.errorWebDavNotConfigured,
      );
    }

    final validationFailure = _validateAndApplyWebDavDraft(localizations);
    if (validationFailure != null) {
      return validationFailure;
    }

    final previousConfig = _persistedConfig;
    final candidateConfig = _buildCandidateWebDavConfig(previousConfig);
    if (!candidateConfig.isWebDavConfigured) {
      final message = localizations.errorWebDavNotConfigured;
      _statusBanner = SettingsStatusBannerViewModel(
        tone: BannerTone.danger,
        message: message,
      );
      state = _buildCurrentViewModel();
      return ActionValidationFailed(message: message);
    }

    return _runGuardedAction(
      localizations: localizations,
      successMessage: localizations.connectionSuccessBanner,
      action: () async {
        await ref
            .read(taskNotifierProvider.notifier)
            .testConnectionAndSync(candidateConfig);
        return true;
      },
      onSuccess: () {
        _applyCommittedConfig(
          previousConfig: previousConfig,
          fallbackConfig: candidateConfig,
          clearWebDavDirty: true,
        );
      },
      onFailure: () {
        final liveConfig = ref.read(webDavConfigProvider).asData?.value;
        if (liveConfig != null) {
          _persistedConfig = liveConfig;
        }
        _isWebDavDirty = _computeIsWebDavDirty(_persistedConfig);
      },
    );
  }

  /// Updates transient WebDAV draft fields, recomputes dirty status and live endpoint preview, and clears edited field errors.
  void updateWebDavDraft({
    String? serverUrl,
    String? username,
    String? password,
    String? filePath,
  }) {
    var edited = false;
    if (serverUrl != null) {
      _draftServerUrl = serverUrl;
      _serverUrlError = null;
      edited = true;
    }
    if (username != null) {
      _draftUsername = username;
      _usernameError = null;
      edited = true;
    }
    if (password != null) {
      _draftPassword = password;
      _passwordError = null;
      edited = true;
    }
    if (filePath != null) {
      _draftFilePath = filePath;
      _filePathError = null;
      edited = true;
    }
    if (!edited) {
      return;
    }
    _isWebDavDirty = _computeIsWebDavDirty(_persistedConfig);
    _statusBanner = null;
    state = _buildCurrentViewModel();
  }

  /// Wipes and re-initializes the local `.tdf` file with optional `.bak` backup creation.
  Future<ActionResult> wipeLocalFile({
    required bool createBackup,
    Locale? locale,
  }) async {
    if (_isBusy) {
      return const ActionSucceeded();
    }
    final localizations = _resolveLocalizations(locale);
    final resolvedPath = ref
        .read(settingsStorageControllerProvider)
        .resolvePreviewLocalPath(_persistedConfig);
    if (resolvedPath == null) {
      final message = localizations.errorInvalidLocalFilePath;
      _statusBanner = SettingsStatusBannerViewModel(
        tone: BannerTone.danger,
        message: message,
      );
      state = _buildCurrentViewModel();
      return ActionValidationFailed(message: message);
    }

    final targetConfig = _persistedConfig;
    final fileName = TdfFilePath.extractFileNameFromPath(
      targetConfig.localFilePath,
    );
    UiTelemetry.logWipeTdfConfirmed(
      targetName: 'local',
      fileName: fileName,
      createBackup: createBackup,
    );
    return _runGuardedAction(
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
    if (_isBusy) {
      return const ActionSucceeded();
    }
    final localizations = _resolveLocalizations(locale);
    if (!_persistedConfig.storageMode.usesWebDav ||
        !_persistedConfig.isWebDavConfigured) {
      final message = localizations.errorWebDavNotConfigured;
      _statusBanner = SettingsStatusBannerViewModel(
        tone: BannerTone.danger,
        message: message,
      );
      state = _buildCurrentViewModel();
      return ActionValidationFailed(message: message);
    }

    final targetConfig = _persistedConfig;
    final fileName = TdfFilePath.extractFileNameFromPath(targetConfig.filePath);
    UiTelemetry.logWipeTdfConfirmed(
      targetName: 'remote',
      fileName: fileName,
      createBackup: createBackup,
    );
    return _runGuardedAction(
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

  /// Updates [_persistedConfig] after a successful write and optionally clears WebDAV dirty state.
  void _applyCommittedConfig({
    required WebDavConfig previousConfig,
    required WebDavConfig fallbackConfig,
    required bool clearWebDavDirty,
  }) {
    final liveConfig = ref.read(webDavConfigProvider).asData?.value;
    final effectiveConfig = (liveConfig != null && liveConfig != previousConfig)
        ? liveConfig
        : fallbackConfig;
    _persistedConfig = effectiveConfig;
    if (clearWebDavDirty) {
      _isWebDavDirty = false;
      _clearValidationErrors();
    }
    if (!_isWebDavDirty) {
      _hydrateDraftFromConfig(effectiveConfig);
    }
  }

  /// Builds a normalized [WebDavConfig] combining [baseConfig] with the current WebDAV draft fields.
  WebDavConfig _buildCandidateWebDavConfig(WebDavConfig baseConfig) {
    final trimmedFilePath = _draftFilePath.trim();
    return baseConfig.copyWith(
      serverUrl: _draftServerUrl.trim(),
      username: _draftUsername.trim(),
      password: _draftPassword,
      filePath: trimmedFilePath.isEmpty
          ? WebDavConfig.defaultFileName
          : trimmedFilePath,
    );
  }

  /// Projects the current persisted config and transient draft/status state into a [SettingsViewModel].
  SettingsViewModel _buildCurrentViewModel() {
    final storageMode = _fromStorageMode(_persistedConfig.storageMode);
    final localFilePath = _persistedConfig.localFilePath.trim().isEmpty
        ? WebDavConfig.defaultFileName
        : _persistedConfig.localFilePath;
    final resolvedLocalPath =
        ref
            .read(settingsStorageControllerProvider)
            .resolvePreviewLocalPath(_persistedConfig) ??
        '';
    final effectiveDraftRemotePath = _draftFilePath.trim().isEmpty
        ? WebDavConfig.defaultFileName
        : _draftFilePath.trim();
    final draftConfig = _buildCandidateWebDavConfig(_persistedConfig);

    return SettingsViewModel(
      workspaceName: _workspaceName,
      language: _fromAppLanguage(_persistedConfig.language),
      themeMode: _fromAppThemeMode(_persistedConfig.themeMode),
      themePalette: _fromAppThemePalette(_persistedConfig.themePalette),
      timeZoneMode: _fromAppTimeZoneMode(_persistedConfig.timeZoneMode),
      manualTimeZoneOffsetMinutes: _persistedConfig.manualTimeZoneOffsetMinutes,
      supportedUtcOffsets: _supportedUtcOffsets,
      dueLeadWindow: _fromDueLeadWindow(_persistedConfig.dueLeadWindow),
      locationEnabled: _persistedConfig.locationEnabled,
      diagnosticsEnabled: _persistedConfig.diagnosticsEnabled,
      logLevel: DiagnosticLogLevel.fromLogLevel(_persistedConfig.logLevel),
      logStorageMode: _fromStorageMode(_persistedConfig.logStorageMode),
      activeLogFileName: _activeLogFileName,
      storageMode: storageMode,
      localFileName: TdfFilePath.extractFileNameFromPath(localFilePath),
      localFileBaseName: TdfFilePath.extractFileBaseName(localFilePath),
      resolvedLocalPath: resolvedLocalPath,
      localWatchEnabled: _persistedConfig.localWatchEnabled,
      supportsNativeDirectoryPicker: _supportsNativeDirectoryPicker,
      webDavServerUrl: _draftServerUrl,
      webDavUsername: _draftUsername,
      webDavPassword: _draftPassword,
      webDavFilePath: _draftFilePath,
      remoteFileBaseName: TdfFilePath.extractFileBaseName(
        effectiveDraftRemotePath,
      ),
      resolvedWebDavEndpoint:
          draftConfig.resolveEndpointUri()?.toString() ?? '',
      isWebDavDirty: _isWebDavDirty,
      isWebDavConfigured: _persistedConfig.isWebDavConfigured,
      canTestConnectionAndSync:
          storageMode != ShellStorageMode.local && !_isBusy,
      isBusy: _isBusy,
      serverUrlError: _serverUrlError,
      usernameError: _usernameError,
      passwordError: _passwordError,
      filePathError: _filePathError,
      statusBanner: _statusBanner,
    );
  }

  /// Clears all four inline WebDAV field validation errors.
  void _clearValidationErrors() {
    _serverUrlError = null;
    _usernameError = null;
    _passwordError = null;
    _filePathError = null;
  }

  /// Returns `true` when any transient WebDAV draft field differs from [persistedConfig].
  bool _computeIsWebDavDirty(WebDavConfig persistedConfig) {
    final persistedFilePath = persistedConfig.filePath.isEmpty
        ? WebDavConfig.defaultFileName
        : persistedConfig.filePath;
    return _draftServerUrl != persistedConfig.serverUrl ||
        _draftUsername != persistedConfig.username ||
        _draftPassword != persistedConfig.password ||
        _draftFilePath != persistedFilePath;
  }

  /// Sets a danger status banner for an invalid local `.tdf` filename and returns a validation failure.
  ActionValidationFailed _failLocalFileNameValidation(
    AppLocalizations localizations,
  ) {
    final message = localizations.localFileNameErrorInvalid;
    _statusBanner = SettingsStatusBannerViewModel(
      tone: BannerTone.danger,
      message: message,
    );
    state = _buildCurrentViewModel();
    return ActionValidationFailed(
      message: message,
      fieldErrors: <String, String>{'localFileName': message},
    );
  }

  /// Silently discards dirty WebDAV edits or stale validation errors when navigating away from Settings (`U-UX-006`).
  void _handleShellViewChanged(ShellView? previous, ShellView next) {
    if (previous != ShellView.settings || next == ShellView.settings) {
      return;
    }
    if (_isWebDavDirty) {
      discardWebDavDraft(reason: 'navigation');
      return;
    }
    if (_hasValidationErrors) {
      _clearValidationErrors();
      state = _buildCurrentViewModel();
    }
  }

  /// Hydrates transient WebDAV draft fields from [config].
  void _hydrateDraftFromConfig(WebDavConfig config) {
    _draftServerUrl = config.serverUrl;
    _draftUsername = config.username;
    _draftPassword = config.password;
    _draftFilePath = config.filePath.isEmpty
        ? WebDavConfig.defaultFileName
        : config.filePath;
  }

  /// Resets all transient draft, busy, validation, and banner state for a newly active workspace.
  void _resetTransientState(WebDavConfig persistedConfig) {
    _isBusy = false;
    _isWebDavDirty = false;
    _clearValidationErrors();
    _statusBanner = null;
    _hydrateDraftFromConfig(persistedConfig);
  }

  /// Resolves localized strings for [locale] or falls back to [appLocaleProvider].
  AppLocalizations _resolveLocalizations(Locale? locale) =>
      lookupAppLocalizations(locale ?? ref.read(appLocaleProvider));

  /// Resolves the target file path for [selectLocalFile] from [chosenFileName] or the native desktop file picker.
  Future<String?> _resolveSelectLocalTargetPath(
    WebDavConfig baseConfig,
    String? chosenFileName,
  ) async {
    final settingsController = ref.read(settingsStorageControllerProvider);
    if (chosenFileName != null) {
      final normalizedName = TdfFilePath.ensureTdfExtension(
        chosenFileName.trim(),
      );
      return settingsController.resolveChosenLocalFileName(
        baseConfig,
        normalizedName,
      );
    }
    final pickedPath = await settingsController.pickNativeLocalFile(baseConfig);
    if (pickedPath == null || pickedPath.trim().isEmpty) {
      return null;
    }
    return pickedPath.trim();
  }

  /// Executes an asynchronous storage [action] with busy guarding, workspace liveness checks, and banner reporting.
  Future<ActionResult> _runGuardedAction({
    required AppLocalizations localizations,
    required String successMessage,
    required Future<bool> Function() action,
    VoidCallback? onSuccess,
    VoidCallback? onFailure,
  }) async {
    final workspaceId = _activeWorkspaceId;
    _isBusy = true;
    _statusBanner = null;
    state = _buildCurrentViewModel();
    try {
      final completed = await action();
      if (!ref.mounted || _activeWorkspaceId != workspaceId) {
        return const ActionSucceeded();
      }
      _isBusy = false;
      if (!completed) {
        state = _buildCurrentViewModel();
        return const ActionSucceeded();
      }
      onSuccess?.call();
      _statusBanner = SettingsStatusBannerViewModel(
        tone: BannerTone.success,
        message: successMessage,
      );
      state = _buildCurrentViewModel();
      return ActionSucceeded(noticeMessage: successMessage);
    } on Object catch (error) {
      final message = _formatSettingsError(error, localizations);
      if (!ref.mounted || _activeWorkspaceId != workspaceId) {
        return ActionPersistFailed(message: message);
      }
      onFailure?.call();
      _isBusy = false;
      _statusBanner = SettingsStatusBannerViewModel(
        tone: BannerTone.danger,
        message: message,
      );
      state = _buildCurrentViewModel();
      return ActionPersistFailed(message: message);
    }
  }

  /// Persists an auto-saved preference transition to [nextConfig], rolling back on failure with a danger banner.
  Future<ActionResult> _savePreference({
    required WebDavConfig nextConfig,
    Locale? locale,
  }) async {
    if (_isBusy) {
      return const ActionSucceeded();
    }
    final previousConfig = _persistedConfig;
    final workspaceId = _activeWorkspaceId;
    final localizations = _resolveLocalizations(locale);
    _isBusy = true;
    _statusBanner = null;
    state = _buildCurrentViewModel();

    try {
      final result = await ref
          .read(settingsStorageControllerProvider)
          .savePreferenceChange(
            previous: previousConfig,
            next: nextConfig,
            locale: locale,
          );
      if (!ref.mounted || _activeWorkspaceId != workspaceId) {
        return const ActionSucceeded();
      }
      _isBusy = false;
      switch (result) {
        case SettingsPreferenceSaved(:final effectiveConfig):
          _persistedConfig = effectiveConfig;
          if (!_isWebDavDirty) {
            _hydrateDraftFromConfig(effectiveConfig);
          }
          state = _buildCurrentViewModel();
          return const ActionSucceeded();
        case SettingsPreferenceSaveFailed(:final localizedMessage):
          _statusBanner = SettingsStatusBannerViewModel(
            tone: BannerTone.danger,
            message: localizedMessage,
          );
          state = _buildCurrentViewModel();
          return ActionPersistFailed(message: localizedMessage);
      }
    } on Object catch (error) {
      final message = _formatSettingsError(error, localizations);
      if (!ref.mounted || _activeWorkspaceId != workspaceId) {
        return ActionPersistFailed(message: message);
      }
      _isBusy = false;
      _statusBanner = SettingsStatusBannerViewModel(
        tone: BannerTone.danger,
        message: message,
      );
      state = _buildCurrentViewModel();
      return ActionPersistFailed(message: message);
    }
  }

  /// Synchronizes workspace identity and hydrates or resets transient WebDAV draft state on rebuild.
  void _syncWorkspaceAndDraft({
    required String? workspaceId,
    required WebDavConfig persistedConfig,
  }) {
    final switchedWorkspace =
        workspaceId != null &&
        _activeWorkspaceId != null &&
        workspaceId != _activeWorkspaceId;
    if (switchedWorkspace) {
      if (_isWebDavDirty) {
        UiTelemetry.logSettingsWebDavDraftDiscarded('workspace_switch');
      }
      _resetTransientState(persistedConfig);
      _activeWorkspaceId = workspaceId;
      return;
    }
    if (workspaceId != null) {
      _activeWorkspaceId = workspaceId;
    }
    if (!_isWebDavDirty) {
      _hydrateDraftFromConfig(persistedConfig);
    }
  }

  /// Validates the current WebDAV draft, updates field errors and top danger banner on failure, and returns `null` when valid.
  ActionValidationFailed? _validateAndApplyWebDavDraft(
    AppLocalizations localizations,
  ) {
    final serverUrlError = _validateServerUrl(_draftServerUrl, localizations);
    final usernameError = _draftUsername.trim().isEmpty
        ? localizations.usernameErrorEmpty
        : null;
    final passwordError = _draftPassword.isEmpty
        ? localizations.passwordErrorEmpty
        : null;
    final filePathError = _validateRemoteFilePath(
      _draftFilePath,
      localizations,
    );

    _serverUrlError = serverUrlError;
    _usernameError = usernameError;
    _passwordError = passwordError;
    _filePathError = filePathError;

    final fieldErrors = <String, String>{
      'serverUrl': ?serverUrlError,
      'username': ?usernameError,
      'password': ?passwordError,
      'filePath': ?filePathError,
    };
    final primaryMessage =
        serverUrlError ?? usernameError ?? passwordError ?? filePathError;
    if (primaryMessage == null) {
      return null;
    }

    _statusBanner = SettingsStatusBannerViewModel(
      tone: BannerTone.danger,
      message: primaryMessage,
    );
    state = _buildCurrentViewModel();
    return ActionValidationFailed(
      message: primaryMessage,
      fieldErrors: fieldErrors,
    );
  }
}

/// Immutable model-free state snapshot projected by [SettingsController] for the Settings view.
@immutable
class SettingsViewModel {
  /// Creates a [SettingsViewModel] with an unmodifiable [supportedUtcOffsets] list.
  SettingsViewModel({
    required this.workspaceName,
    required this.language,
    required this.themeMode,
    required this.themePalette,
    required this.timeZoneMode,
    required this.manualTimeZoneOffsetMinutes,
    required Iterable<UtcOffsetOptionViewModel> supportedUtcOffsets,
    required this.dueLeadWindow,
    required this.locationEnabled,
    required this.diagnosticsEnabled,
    required this.logLevel,
    required this.logStorageMode,
    required this.activeLogFileName,
    required this.storageMode,
    required this.localFileName,
    required this.localFileBaseName,
    required this.resolvedLocalPath,
    required this.localWatchEnabled,
    required this.supportsNativeDirectoryPicker,
    required this.webDavServerUrl,
    required this.webDavUsername,
    required this.webDavPassword,
    required this.webDavFilePath,
    required this.remoteFileBaseName,
    required this.resolvedWebDavEndpoint,
    required this.isWebDavDirty,
    required this.isWebDavConfigured,
    required this.canTestConnectionAndSync,
    required this.isBusy,
    this.serverUrlError,
    this.usernameError,
    this.passwordError,
    this.filePathError,
    this.statusBanner,
  }) : supportedUtcOffsets = List<UtcOffsetOptionViewModel>.unmodifiable(
         supportedUtcOffsets,
       );

  /// Live dated diagnostic log filename (`tiertask_<date>_<platform>_<workspace>.log`).
  final String activeLogFileName;

  /// Whether WebDAV connection testing and synchronization is currently actionable.
  final bool canTestConnectionAndSync;

  /// Whether opt-in diagnostic logging is enabled.
  final bool diagnosticsEnabled;

  /// Per-workspace deadline lead window option.
  final ShellDueLeadOption dueLeadWindow;

  /// Inline validation error for the remote WebDAV `.tdf` file path field, if any.
  final String? filePathError;

  /// Whether an asynchronous settings save, file, wipe, or sync operation is in flight.
  final bool isBusy;

  /// Whether persisted WebDAV credentials and server URL are fully configured.
  final bool isWebDavConfigured;

  /// Whether the WebDAV draft form has uncommitted edits compared to persisted configuration.
  final bool isWebDavDirty;

  /// Active display language preference.
  final ShellLanguageOption language;

  /// Base local filename without `.tdf` extension for typed-filename Wipe confirmation.
  final String localFileBaseName;

  /// Local `.tdf` filename without parent directory path.
  final String localFileName;

  /// Whether automatic external local `.tdf` directory observation is enabled.
  final bool localWatchEnabled;

  /// Whether foreground location determination is enabled.
  final bool locationEnabled;

  /// Minimum diagnostic log severity threshold.
  final DiagnosticLogLevel logLevel;

  /// Persistence target for diagnostic logs (`local`, `webdav`, or `both`).
  final ShellStorageMode logStorageMode;

  /// Manual UTC offset in minutes (`-720..840`) when [timeZoneMode] is [ShellTimeZoneMode.manual].
  final int manualTimeZoneOffsetMinutes;

  /// Inline validation error for the WebDAV password field, if any.
  final String? passwordError;

  /// Remote `.tdf` base filename without `.tdf` extension for typed-filename Wipe confirmation.
  final String remoteFileBaseName;

  /// Resolved local `.tdf` filesystem path preview, or empty when invalid.
  final String resolvedLocalPath;

  /// Live resolved WebDAV endpoint URI preview from draft values, or empty when invalid.
  final String resolvedWebDavEndpoint;

  /// Inline validation error for the WebDAV server URL field, if any.
  final String? serverUrlError;

  /// Active top status banner in Settings, if any.
  final SettingsStatusBannerViewModel? statusBanner;

  /// Active task board persistence mode (`local`, `webdav`, or `both`).
  final ShellStorageMode storageMode;

  /// All 37 selectable manual UTC offset options (`UTC-12:00` through `UTC+14:00`).
  final List<UtcOffsetOptionViewModel> supportedUtcOffsets;

  /// Whether the active host platform supports native directory and file picking.
  final bool supportsNativeDirectoryPicker;

  /// Active light/dark/system brightness preference.
  final ShellThemeMode themeMode;

  /// Active design-system color palette preset (`calm` or `plum_umber`).
  final AppThemePresetKey themePalette;

  /// Active time zone resolution mode (`automatic` or `manual`).
  final ShellTimeZoneMode timeZoneMode;

  /// Inline validation error for the WebDAV username field, if any.
  final String? usernameError;

  /// Transient draft value of the remote WebDAV `.tdf` file path field.
  final String webDavFilePath;

  /// Transient draft value of the WebDAV password field.
  final String webDavPassword;

  /// Transient draft value of the WebDAV server URL field.
  final String webDavServerUrl;

  /// Transient draft value of the WebDAV username field.
  final String webDavUsername;

  /// Display name of the currently active workspace.
  final String workspaceName;

  /// Returns a copy of this [SettingsViewModel] with selectively updated fields.
  SettingsViewModel copyWith({
    String? workspaceName,
    ShellLanguageOption? language,
    ShellThemeMode? themeMode,
    AppThemePresetKey? themePalette,
    ShellTimeZoneMode? timeZoneMode,
    int? manualTimeZoneOffsetMinutes,
    Iterable<UtcOffsetOptionViewModel>? supportedUtcOffsets,
    ShellDueLeadOption? dueLeadWindow,
    bool? locationEnabled,
    bool? diagnosticsEnabled,
    DiagnosticLogLevel? logLevel,
    ShellStorageMode? logStorageMode,
    String? activeLogFileName,
    ShellStorageMode? storageMode,
    String? localFileName,
    String? localFileBaseName,
    String? resolvedLocalPath,
    bool? localWatchEnabled,
    bool? supportsNativeDirectoryPicker,
    String? webDavServerUrl,
    String? webDavUsername,
    String? webDavPassword,
    String? webDavFilePath,
    String? remoteFileBaseName,
    String? resolvedWebDavEndpoint,
    bool? isWebDavDirty,
    bool? isWebDavConfigured,
    bool? canTestConnectionAndSync,
    bool? isBusy,
    String? serverUrlError,
    bool clearServerUrlError = false,
    String? usernameError,
    bool clearUsernameError = false,
    String? passwordError,
    bool clearPasswordError = false,
    String? filePathError,
    bool clearFilePathError = false,
    SettingsStatusBannerViewModel? statusBanner,
    bool clearStatusBanner = false,
  }) {
    return SettingsViewModel(
      workspaceName: workspaceName ?? this.workspaceName,
      language: language ?? this.language,
      themeMode: themeMode ?? this.themeMode,
      themePalette: themePalette ?? this.themePalette,
      timeZoneMode: timeZoneMode ?? this.timeZoneMode,
      manualTimeZoneOffsetMinutes:
          manualTimeZoneOffsetMinutes ?? this.manualTimeZoneOffsetMinutes,
      supportedUtcOffsets: supportedUtcOffsets ?? this.supportedUtcOffsets,
      dueLeadWindow: dueLeadWindow ?? this.dueLeadWindow,
      locationEnabled: locationEnabled ?? this.locationEnabled,
      diagnosticsEnabled: diagnosticsEnabled ?? this.diagnosticsEnabled,
      logLevel: logLevel ?? this.logLevel,
      logStorageMode: logStorageMode ?? this.logStorageMode,
      activeLogFileName: activeLogFileName ?? this.activeLogFileName,
      storageMode: storageMode ?? this.storageMode,
      localFileName: localFileName ?? this.localFileName,
      localFileBaseName: localFileBaseName ?? this.localFileBaseName,
      resolvedLocalPath: resolvedLocalPath ?? this.resolvedLocalPath,
      localWatchEnabled: localWatchEnabled ?? this.localWatchEnabled,
      supportsNativeDirectoryPicker:
          supportsNativeDirectoryPicker ?? this.supportsNativeDirectoryPicker,
      webDavServerUrl: webDavServerUrl ?? this.webDavServerUrl,
      webDavUsername: webDavUsername ?? this.webDavUsername,
      webDavPassword: webDavPassword ?? this.webDavPassword,
      webDavFilePath: webDavFilePath ?? this.webDavFilePath,
      remoteFileBaseName: remoteFileBaseName ?? this.remoteFileBaseName,
      resolvedWebDavEndpoint:
          resolvedWebDavEndpoint ?? this.resolvedWebDavEndpoint,
      isWebDavDirty: isWebDavDirty ?? this.isWebDavDirty,
      isWebDavConfigured: isWebDavConfigured ?? this.isWebDavConfigured,
      canTestConnectionAndSync:
          canTestConnectionAndSync ?? this.canTestConnectionAndSync,
      isBusy: isBusy ?? this.isBusy,
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
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SettingsViewModel &&
        other.workspaceName == workspaceName &&
        other.language == language &&
        other.themeMode == themeMode &&
        other.themePalette == themePalette &&
        other.timeZoneMode == timeZoneMode &&
        other.manualTimeZoneOffsetMinutes == manualTimeZoneOffsetMinutes &&
        listEquals(other.supportedUtcOffsets, supportedUtcOffsets) &&
        other.dueLeadWindow == dueLeadWindow &&
        other.locationEnabled == locationEnabled &&
        other.diagnosticsEnabled == diagnosticsEnabled &&
        other.logLevel == logLevel &&
        other.logStorageMode == logStorageMode &&
        other.activeLogFileName == activeLogFileName &&
        other.storageMode == storageMode &&
        other.localFileName == localFileName &&
        other.localFileBaseName == localFileBaseName &&
        other.resolvedLocalPath == resolvedLocalPath &&
        other.localWatchEnabled == localWatchEnabled &&
        other.supportsNativeDirectoryPicker == supportsNativeDirectoryPicker &&
        other.webDavServerUrl == webDavServerUrl &&
        other.webDavUsername == webDavUsername &&
        other.webDavPassword == webDavPassword &&
        other.webDavFilePath == webDavFilePath &&
        other.remoteFileBaseName == remoteFileBaseName &&
        other.resolvedWebDavEndpoint == resolvedWebDavEndpoint &&
        other.isWebDavDirty == isWebDavDirty &&
        other.isWebDavConfigured == isWebDavConfigured &&
        other.canTestConnectionAndSync == canTestConnectionAndSync &&
        other.isBusy == isBusy &&
        other.serverUrlError == serverUrlError &&
        other.usernameError == usernameError &&
        other.passwordError == passwordError &&
        other.filePathError == filePathError &&
        other.statusBanner == statusBanner;
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
    workspaceName,
    language,
    themeMode,
    themePalette,
    timeZoneMode,
    manualTimeZoneOffsetMinutes,
    Object.hashAll(supportedUtcOffsets),
    dueLeadWindow,
    locationEnabled,
    diagnosticsEnabled,
    logLevel,
    logStorageMode,
    activeLogFileName,
    storageMode,
    localFileName,
    localFileBaseName,
    resolvedLocalPath,
    localWatchEnabled,
    supportsNativeDirectoryPicker,
    webDavServerUrl,
    webDavUsername,
    webDavPassword,
    webDavFilePath,
    remoteFileBaseName,
    resolvedWebDavEndpoint,
    isWebDavDirty,
    isWebDavConfigured,
    canTestConnectionAndSync,
    isBusy,
    serverUrlError,
    usernameError,
    passwordError,
    filePathError,
    statusBanner,
  ]);

  @override
  String toString() =>
      'SettingsViewModel(workspaceName: $workspaceName, '
      'storageMode: ${storageMode.name}, '
      'webDavServerUrl: $webDavServerUrl, '
      'webDavUsername: $webDavUsername, '
      'webDavPassword: ${webDavPassword.isEmpty ? "" : "[REDACTED]"}, '
      'isWebDavDirty: $isWebDavDirty, isBusy: $isBusy)';
}

/// Immutable option describing one selectable fixed UTC offset entry (`UTC±HH:MM`).
@immutable
class UtcOffsetOptionViewModel {
  /// Creates a [UtcOffsetOptionViewModel].
  const UtcOffsetOptionViewModel({
    required this.offsetMinutes,
    required this.label,
  });

  /// Formatted ISO-style UTC offset label (e.g. `UTC+01:00`).
  final String label;

  /// Offset from UTC in signed minutes (`-720..840`).
  final int offsetMinutes;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UtcOffsetOptionViewModel &&
        other.offsetMinutes == offsetMinutes &&
        other.label == label;
  }

  @override
  int get hashCode => Object.hash(offsetMinutes, label);
}

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

/// Maps [AppLanguage] to its model-free [ShellLanguageOption] counterpart.
ShellLanguageOption _fromAppLanguage(AppLanguage language) {
  return switch (language) {
    AppLanguage.system => ShellLanguageOption.system,
    AppLanguage.english => ShellLanguageOption.english,
    AppLanguage.german => ShellLanguageOption.german,
  };
}

/// Maps [AppThemeMode] to its model-free [ShellThemeMode] counterpart.
ShellThemeMode _fromAppThemeMode(AppThemeMode themeMode) {
  return switch (themeMode) {
    AppThemeMode.system => ShellThemeMode.system,
    AppThemeMode.light => ShellThemeMode.light,
    AppThemeMode.dark => ShellThemeMode.dark,
  };
}

/// Maps [AppThemePalette] to its model-free [AppThemePresetKey] counterpart.
AppThemePresetKey _fromAppThemePalette(AppThemePalette palette) {
  return switch (palette) {
    AppThemePalette.calm => AppThemePresetKey.calm,
    AppThemePalette.plumUmber => AppThemePresetKey.plumUmber,
  };
}

/// Maps [AppTimeZoneMode] to its model-free [ShellTimeZoneMode] counterpart.
ShellTimeZoneMode _fromAppTimeZoneMode(AppTimeZoneMode timeZoneMode) {
  return switch (timeZoneMode) {
    AppTimeZoneMode.automatic => ShellTimeZoneMode.automatic,
    AppTimeZoneMode.manual => ShellTimeZoneMode.manual,
  };
}

/// Maps [DueLeadWindow] to its model-free [ShellDueLeadOption] counterpart.
ShellDueLeadOption _fromDueLeadWindow(DueLeadWindow dueLeadWindow) {
  return switch (dueLeadWindow) {
    DueLeadWindow.off => ShellDueLeadOption.off,
    DueLeadWindow.atDue => ShellDueLeadOption.atDue,
    DueLeadWindow.hours12 => ShellDueLeadOption.hours12,
    DueLeadWindow.hours24 => ShellDueLeadOption.hours24,
    DueLeadWindow.hours48 => ShellDueLeadOption.hours48,
    DueLeadWindow.days7 => ShellDueLeadOption.days7,
  };
}

/// Maps [StorageMode] to its model-free [ShellStorageMode] counterpart.
ShellStorageMode _fromStorageMode(StorageMode storageMode) {
  return switch (storageMode) {
    StorageMode.local => ShellStorageMode.local,
    StorageMode.webdav => ShellStorageMode.webdav,
    StorageMode.both => ShellStorageMode.both,
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

/// Returns `true` when [rawName] is a safe single local `.tdf` filename without path separators, `..`, or control characters.
bool _isValidLocalSingleFileName(String rawName) {
  if (_hasControlCharacters(rawName)) {
    return false;
  }
  final trimmed = rawName.trim();
  return TdfFilePath.isValidSingleFileName(trimmed) && !trimmed.contains('..');
}

/// Maps [ShellLanguageOption] back to [AppLanguage].
AppLanguage _toAppLanguage(ShellLanguageOption language) {
  return switch (language) {
    ShellLanguageOption.system => AppLanguage.system,
    ShellLanguageOption.english => AppLanguage.english,
    ShellLanguageOption.german => AppLanguage.german,
  };
}

/// Maps [ShellThemeMode] back to [AppThemeMode].
AppThemeMode _toAppThemeMode(ShellThemeMode themeMode) {
  return switch (themeMode) {
    ShellThemeMode.system => AppThemeMode.system,
    ShellThemeMode.light => AppThemeMode.light,
    ShellThemeMode.dark => AppThemeMode.dark,
  };
}

/// Maps [AppThemePresetKey] back to [AppThemePalette].
AppThemePalette _toAppThemePalette(AppThemePresetKey presetKey) {
  return switch (presetKey) {
    AppThemePresetKey.calm => AppThemePalette.calm,
    AppThemePresetKey.plumUmber => AppThemePalette.plumUmber,
  };
}

/// Maps [ShellTimeZoneMode] back to [AppTimeZoneMode].
AppTimeZoneMode _toAppTimeZoneMode(ShellTimeZoneMode timeZoneMode) {
  return switch (timeZoneMode) {
    ShellTimeZoneMode.automatic => AppTimeZoneMode.automatic,
    ShellTimeZoneMode.manual => AppTimeZoneMode.manual,
  };
}

/// Maps [ShellDueLeadOption] back to [DueLeadWindow].
DueLeadWindow _toDueLeadWindow(ShellDueLeadOption option) {
  return switch (option) {
    ShellDueLeadOption.off => DueLeadWindow.off,
    ShellDueLeadOption.atDue => DueLeadWindow.atDue,
    ShellDueLeadOption.hours12 => DueLeadWindow.hours12,
    ShellDueLeadOption.hours24 => DueLeadWindow.hours24,
    ShellDueLeadOption.hours48 => DueLeadWindow.hours48,
    ShellDueLeadOption.days7 => DueLeadWindow.days7,
  };
}

/// Maps [ShellStorageMode] back to [StorageMode].
StorageMode _toStorageMode(ShellStorageMode storageMode) {
  return switch (storageMode) {
    ShellStorageMode.local => StorageMode.local,
    ShellStorageMode.webdav => StorageMode.webdav,
    ShellStorageMode.both => StorageMode.both,
  };
}

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
