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
import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import '../models/webdav_config.dart';
import '../providers/config_providers.dart';
import '../providers/task_providers.dart';
import '../repositories/local_file_repository.dart';
import 'widgets/settings_local_storage_section.dart';
import 'widgets/settings_preference_cards.dart';
import 'widgets/settings_webdav_storage_section.dart';
import 'widgets/wipe_tdf_dialog.dart';

/// Action buttons row for saving settings or testing synchronization.
class SettingsActionRow extends StatelessWidget {
  /// Creates a [SettingsActionRow].
  const SettingsActionRow({
    super.key,
    required this.canTestConnection,
    required this.isTesting,
    required this.onSaveOnly,
    required this.onTestAndSync,
  });

  /// Whether WebDAV connection testing is enabled for the active storage mode.
  final bool canTestConnection;

  /// Whether a synchronization test is currently running.
  final bool isTesting;

  /// Callback to save settings without running an immediate sync test.
  final VoidCallback onSaveOnly;

  /// Callback to test storage access and synchronize now.
  final VoidCallback onTestAndSync;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final syncIcon = isTesting
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.sync_rounded);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: isTesting ? null : onSaveOnly,
              icon: const Icon(Icons.save_outlined),
              label: Text(localizations.actionSave),
            ),
          ),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: (canTestConnection && !isTesting)
                  ? onTestAndSync
                  : null,
              icon: syncIcon,
              label: Text(localizations.actionTestConnectionAndSync),
            ),
          ),
        ],
      ),
    );
  }
}

/// Settings screen for language, color theme, storage mode, local file name, and WebDAV parameters.
class SettingsScreen extends ConsumerStatefulWidget {
  /// Creates a [SettingsScreen] widget.
  const SettingsScreen({super.key});

  /// Duration a status banner stays fully visible before fading out.
  static const Duration statusBannerDisplayDuration = Duration(seconds: 3);

  /// Duration of the status banner fade-out animation.
  static const Duration statusBannerFadeDuration = Duration(milliseconds: 300);

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

/// Floating status banner displaying save confirmation or synchronization messages above the bottom action row.
class SettingsStatusBanner extends StatelessWidget {
  /// Creates a [SettingsStatusBanner].
  const SettingsStatusBanner({
    super.key,
    required this.isVisible,
    required this.message,
    required this.onFadeOutComplete,
    required this.tone,
  });

  /// Whether the banner is currently opaque (`true`) or fading out (`false`).
  final bool isVisible;

  /// Status message text.
  final String message;

  /// Callback invoked when the opacity animation finishes.
  final VoidCallback onFadeOutComplete;

  /// Visual tone (`success` or `error`).
  final StatusBannerTone tone;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isError = tone == StatusBannerTone.error;
    final foregroundColor = isError
        ? colorScheme.onErrorContainer
        : colorScheme.onPrimaryContainer;
    final icon = isError
        ? Icons.error_outline_rounded
        : Icons.check_circle_outline_rounded;

    return Positioned(
      left: 16,
      right: 16,
      bottom: 8,
      child: AnimatedOpacity(
        opacity: isVisible ? 1.0 : 0.0,
        duration: SettingsScreen.statusBannerFadeDuration,
        curve: Curves.easeOut,
        onEnd: onFadeOutComplete,
        child: Material(
          elevation: 4,
          color: isError
              ? colorScheme.errorContainer
              : colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              spacing: 10,
              children: [
                Icon(icon, color: foregroundColor),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(color: foregroundColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Visual tone for [SettingsStatusBanner].
enum StatusBannerTone {
  /// Indicates a completed save, move, rename, wipe, or synchronization action.
  success,

  /// Indicates a validation, filesystem, or synchronization failure.
  error,
}

/// State for [SettingsScreen].
class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Timer? _bannerTimer;
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _filePathController;
  late final TextEditingController _passwordController;
  late final TextEditingController _serverUrlController;
  late final TextEditingController _usernameController;

  bool _initialized = false;
  bool _isBannerVisible = false;
  bool _isTesting = false;
  bool _obscurePassword = true;
  WebDavConfig _preferences = const WebDavConfig();
  String? _statusBannerMessage;
  StatusBannerTone _statusTone = StatusBannerTone.success;

  @override
  void initState() {
    super.initState();
    _serverUrlController = TextEditingController();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _filePathController = TextEditingController(
      text: WebDavConfig.defaultFileName,
    );
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _filePathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(webDavConfigProvider).asData?.value case final loaded?) {
      _populateFieldsIfNeeded(loaded);
    }
    final currentConfig = _buildCurrentConfig();
    final bannerMessage = _statusBannerMessage;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: Text(AppLocalizations.of(context).settingsTitle)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          onChanged: () => setState(_clearStatusBanner),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: _buildFormColumn(currentConfig),
                    ),
                    if (bannerMessage != null)
                      SettingsStatusBanner(
                        isVisible: _isBannerVisible,
                        message: bannerMessage,
                        tone: _statusTone,
                        onFadeOutComplete: () {
                          if (mounted && !_isBannerVisible) {
                            setState(() => _statusBannerMessage = null);
                          }
                        },
                      ),
                  ],
                ),
              ),
              SettingsActionRow(
                canTestConnection: _preferences.storageMode.usesWebDav,
                isTesting: _isTesting,
                onSaveOnly: _saveOnly,
                onTestAndSync: _testConnectionAndSync,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Resolves a local file path via [pickPath], runs [operation], and updates [_preferences] and the status banner.
  Future<void> _applyLocalFileUpdate(
    FutureOr<String?> Function(WebDavConfig config) pickPath, {
    Future<void> Function(WebDavConfig)? operation,
    required String Function(AppLocalizations) bannerSelector,
  }) async {
    setState(_clearStatusBanner);
    final targetFilePath = await pickPath(_buildCurrentConfig());
    if (!mounted || targetFilePath == null || targetFilePath.trim().isEmpty) {
      return;
    }
    final candidateConfig = _buildCurrentConfig(
      localFilePathOverride: targetFilePath,
    );
    try {
      final effectiveOperation =
          operation ??
          ref.read(webDavConfigProvider.notifier).changeLocalFileLocation;
      await effectiveOperation(candidateConfig);
      if (!mounted) {
        return;
      }
      final localizations = AppLocalizations.of(context);
      setState(() {
        _preferences = _preferences.copyWith(
          localFilePath: candidateConfig.localFilePath,
        );
      });
      _showStatusBanner(
        bannerSelector(localizations),
        StatusBannerTone.success,
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      _showStatusBanner(error.toString(), StatusBannerTone.error);
    }
  }

  /// Constructs a [WebDavConfig] from the current form field values and [_preferences].
  WebDavConfig _buildCurrentConfig({String? localFilePathOverride}) {
    final rawLocal = (localFilePathOverride ?? _preferences.localFilePath)
        .trim();
    final filePath = _filePathController.text.trim();
    return _preferences.copyWith(
      serverUrl: _serverUrlController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      filePath: filePath.isEmpty ? WebDavConfig.defaultFileName : filePath,
      localFilePath: rawLocal.isEmpty ? WebDavConfig.defaultFileName : rawLocal,
    );
  }

  /// Builds the scrollable preference and storage section card column for [currentConfig].
  Widget _buildFormColumn(WebDavConfig currentConfig) {
    final canPickDirectory = ref.watch(supportsDirectoryPickerProvider);
    final storageMode = _preferences.storageMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        SettingsPreferenceCards(
          config: currentConfig,
          onPreferenceChanged: _handlePreferenceChanged,
        ),
        if (storageMode.usesLocal)
          LocalStorageSection(
            resolvedLocalPath: _resolvePreviewLocalPath(currentConfig),
            localWatchEnabled: _preferences.localWatchEnabled,
            onLocalWatchEnabledChanged: _isTesting
                ? null
                : _handleLocalWatchChanged,
            onSelectLocalFile: _isTesting ? null : _handleSelectLocalFile,
            onMoveLocalFile: (!canPickDirectory || _isTesting)
                ? null
                : () => _handleMoveOrRenameLocalFile(rename: false),
            onRenameLocalFile: _isTesting
                ? null
                : () => _handleMoveOrRenameLocalFile(rename: true),
            onWipeLocalFile: _isTesting
                ? null
                : () => _handleWipeFile(isRemote: false),
          ),
        if (storageMode.usesWebDav)
          WebDavStorageSection(
            serverUrlController: _serverUrlController,
            usernameController: _usernameController,
            passwordController: _passwordController,
            filePathController: _filePathController,
            obscurePassword: _obscurePassword,
            resolvedUri: currentConfig.resolveEndpointUri(),
            onToggleObscurePassword: () =>
                setState(() => _obscurePassword = !_obscurePassword),
            onWipeRemoteFile: _isTesting
                ? null
                : () => _handleWipeFile(isRemote: true),
          ),
      ],
    );
  }

  /// Cancels any active banner timer and hides the status banner immediately.
  void _clearStatusBanner() {
    _bannerTimer?.cancel();
    _bannerTimer = null;
    _isBannerVisible = false;
    _statusBannerMessage = null;
  }

  /// Executes an asynchronous storage [action] while setting [_isTesting] and showing [bannerSelector] on completion.
  Future<void> _executeStorageAction(
    Future<void> Function() action, {
    required String Function(AppLocalizations) bannerSelector,
  }) async {
    setState(() => _isTesting = true);
    try {
      await action();
      if (!mounted) {
        return;
      }
      final localizations = AppLocalizations.of(context);
      _isTesting = false;
      _showStatusBanner(
        bannerSelector(localizations),
        StatusBannerTone.success,
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      _isTesting = false;
      _showStatusBanner(error.toString(), StatusBannerTone.error);
    }
  }

  /// Toggles automatic local `.tdf` file watching via [_handlePreferenceChanged].
  Future<void> _handleLocalWatchChanged(bool enabled) {
    return _handlePreferenceChanged(
      _buildCurrentConfig().copyWith(localWatchEnabled: enabled),
    );
  }

  /// Moves (`rename: false`) or renames (`rename: true`) the local `.tdf` file and updates state.
  Future<void> _handleMoveOrRenameLocalFile({required bool rename}) {
    return _applyLocalFileUpdate(
      (config) => LocalStorageSection.pickLocalFilePath(
        context,
        ref,
        config,
        moveDirectory: !rename,
        renameOnly: rename,
      ),
      bannerSelector: (localizations) => rename
          ? localizations.localFileRenamedBanner
          : localizations.localDirectoryMovedBanner,
    );
  }

  /// Updates [_preferences], clears any status banner, and persists [updatedConfig] via [webDavConfigProvider].
  Future<void> _handlePreferenceChanged(WebDavConfig updatedConfig) async {
    final diagnosticsChanged =
        updatedConfig.diagnosticsEnabled != _preferences.diagnosticsEnabled;
    final localWatchChanged =
        updatedConfig.localWatchEnabled != _preferences.localWatchEnabled;
    final logLevelChanged = updatedConfig.logLevel != _preferences.logLevel;
    final logStorageChanged =
        updatedConfig.logStorageMode != _preferences.logStorageMode;
    setState(() {
      _preferences = updatedConfig;
      _clearStatusBanner();
    });
    final notifier = ref.read(webDavConfigProvider.notifier);
    if (diagnosticsChanged) {
      await notifier.updateDiagnosticsEnabled(updatedConfig.diagnosticsEnabled);
    } else if (localWatchChanged) {
      await notifier.updateLocalWatchEnabled(updatedConfig.localWatchEnabled);
    } else if (logLevelChanged) {
      await notifier.updateLogLevel(updatedConfig.logLevel);
    } else if (logStorageChanged) {
      await notifier.updateLogStorageMode(updatedConfig.logStorageMode);
    } else {
      await notifier.updateConfig(updatedConfig);
    }
  }

  /// Opens the native file chooser (or in-app dialog fallback on Android) to select or create a `.tdf` file.
  Future<void> _handleSelectLocalFile() {
    return _applyLocalFileUpdate(
      (config) => LocalStorageSection.pickLocalFilePath(context, ref, config),
      operation: ref.read(taskNotifierProvider.notifier).selectLocalFile,
      bannerSelector: (localizations) => localizations.localFileSelectedBanner,
    );
  }

  /// Opens [WipeTdfDialog] for the local (`isRemote: false`) or remote (`isRemote: true`) `.tdf` file and wipes it if confirmed.
  Future<void> _handleWipeFile({required bool isRemote}) async {
    setState(_clearStatusBanner);
    if (isRemote && !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final currentConfig = _buildCurrentConfig();
    final localizations = AppLocalizations.of(context);
    if (isRemote && !currentConfig.isWebDavConfigured) {
      _showStatusBanner(
        localizations.errorWebDavNotConfigured,
        StatusBannerTone.error,
      );
      return;
    }
    if (!isRemote && _resolvePreviewLocalPath(currentConfig) == null) {
      _showStatusBanner(
        localizations.errorInvalidLocalFilePath,
        StatusBannerTone.error,
      );
      return;
    }
    final targetPath = isRemote
        ? currentConfig.filePath
        : currentConfig.localFilePath;
    final dialogResult = await showWipeTdfDialog(
      context,
      target: isRemote ? WipeTdfTarget.remote : WipeTdfTarget.local,
      fileName: LocalFileRepository.extractFileNameFromPath(targetPath),
      expectedBaseName: LocalFileRepository.extractFileBaseName(targetPath),
    );
    if (!mounted || dialogResult == null) {
      return;
    }
    final notifier = ref.read(taskNotifierProvider.notifier);
    await _executeStorageAction(
      () => isRemote
          ? notifier.wipeRemoteFile(
              currentConfig,
              createBackup: dialogResult.createBackup,
            )
          : notifier.wipeLocalFile(
              currentConfig,
              createBackup: dialogResult.createBackup,
            ),
      bannerSelector: (loc) =>
          isRemote ? loc.remoteFileWipedBanner : loc.localFileWipedBanner,
    );
  }

  /// Synchronizes [_preferences] and initializes the text controllers once when [config] finishes loading.
  void _populateFieldsIfNeeded(WebDavConfig config) {
    final rawLocal = config.localFilePath.trim();
    _preferences = config.copyWith(
      localFilePath: rawLocal.isEmpty ? WebDavConfig.defaultFileName : rawLocal,
    );
    if (_initialized) {
      return;
    }
    _initialized = true;
    _serverUrlController.text = config.serverUrl;
    _usernameController.text = config.username;
    _passwordController.text = config.password;
    _filePathController.text = config.filePath.isEmpty
        ? WebDavConfig.defaultFileName
        : config.filePath;
  }

  /// Resolves the preview local file path for [config], or `null` if invalid.
  String? _resolvePreviewLocalPath(WebDavConfig config) {
    return LocalFileRepository(
      config: config,
      baseDirectoryPath: ref.read(localStorageDirectoryPathProvider),
    ).tryResolveFilePath();
  }

  /// Validates and persists the current settings without triggering a remote sync.
  Future<void> _saveOnly() async {
    setState(_clearStatusBanner);
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    await _applyLocalFileUpdate(
      (config) => config.localFilePath,
      bannerSelector: (localizations) => localizations.credentialsSavedBanner,
    );
  }

  /// Displays [message] with [tone] and schedules an automatic fade-out.
  void _showStatusBanner(String message, StatusBannerTone tone) {
    _bannerTimer?.cancel();
    setState(() {
      _statusTone = tone;
      _statusBannerMessage = message;
      _isBannerVisible = true;
    });
    _bannerTimer = Timer(SettingsScreen.statusBannerDisplayDuration, () {
      if (mounted) {
        setState(() => _isBannerVisible = false);
      }
    });
  }

  /// Validates the form, saves [WebDavConfig], and runs a storage synchronization test.
  Future<void> _testConnectionAndSync() async {
    setState(_clearStatusBanner);
    if (!_preferences.storageMode.usesWebDav) {
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final config = _buildCurrentConfig();
    if (!config.isWebDavConfigured) {
      _showStatusBanner(
        AppLocalizations.of(context).errorWebDavNotConfigured,
        StatusBannerTone.error,
      );
      return;
    }
    await _executeStorageAction(
      () =>
          ref.read(taskNotifierProvider.notifier).testConnectionAndSync(config),
      bannerSelector: (localizations) => localizations.connectionSuccessBanner,
    );
  }
}
