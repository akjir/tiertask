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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/webdav_config.dart';
import '../providers/task_providers.dart';
import '../repositories/local_file_repository.dart';
import 'widgets/clearable_text_field.dart';

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

/// Card for enabling or disabling the opt-in diagnostic log (`tiertask.log`).
class _DiagnosticsSelectionCard extends StatelessWidget {
  /// Creates a [_DiagnosticsSelectionCard].
  const _DiagnosticsSelectionCard({
    required this.diagnosticsEnabled,
    required this.onDiagnosticsEnabledChanged,
  });

  /// Whether opt-in diagnostic logging is currently enabled.
  final bool diagnosticsEnabled;

  /// Callback invoked when the user toggles the diagnostic logging switch.
  final ValueChanged<bool> onDiagnosticsEnabledChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return _SettingsSectionCard(
      icon: Icons.bug_report_outlined,
      title: localizations.diagnosticsSectionTitle,
      description: localizations.diagnosticsSectionDescription,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Switch(
          key: const ValueKey('settings_diagnostics_switch'),
          value: diagnosticsEnabled,
          onChanged: onDiagnosticsEnabledChanged,
        ),
      ),
    );
  }
}

/// Card for choosing the application display language (`System`, `English`, or `Deutsch`).
class _LanguageSelectionCard extends StatelessWidget {
  /// Creates a [_LanguageSelectionCard].
  const _LanguageSelectionCard({
    required this.selectedLanguage,
    required this.onLanguageChanged,
  });

  /// Callback invoked when the user selects a new [AppLanguage].
  final ValueChanged<AppLanguage> onLanguageChanged;

  /// Currently selected [AppLanguage].
  final AppLanguage selectedLanguage;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return _SettingsSectionCard(
      icon: Icons.language_rounded,
      title: localizations.languageSectionTitle,
      description: localizations.languageSectionDescription,
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<AppLanguage>(
          segments: [
            ButtonSegment(
              value: AppLanguage.system,
              label: Text(localizations.languageSystem),
            ),
            ButtonSegment(
              value: AppLanguage.english,
              label: Text(localizations.languageEnglish),
            ),
            ButtonSegment(
              value: AppLanguage.german,
              label: Text(localizations.languageGerman),
            ),
          ],
          selected: {selectedLanguage},
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) {
              onLanguageChanged(selection.first);
            }
          },
        ),
      ),
    );
  }
}

/// Card for configuring the local Markdown file name and previewing its resolved path.
class _LocalStorageSection extends StatelessWidget {
  /// Creates a [_LocalStorageSection].
  const _LocalStorageSection({
    required this.localFilePathController,
    required this.resolvedLocalPath,
    this.onChangeDirectory,
  });

  /// Controller for the local Markdown file name or path field.
  final TextEditingController localFilePathController;

  /// Optional callback to open the native desktop directory picker on Linux and Windows.
  final VoidCallback? onChangeDirectory;

  /// Resolved local filesystem path preview, or `null` if invalid.
  final String? resolvedLocalPath;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final previewPath = resolvedLocalPath;

    return _SettingsSectionCard(
      icon: Icons.folder_outlined,
      title: localizations.localSectionTitle,
      description: localizations.localSectionDescription,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClearableTextField(
            useFormField: true,
            controller: localFilePathController,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: localizations.localFilePathLabel,
              hintText: localizations.localFilePathHint,
              prefixIcon: const Icon(Icons.insert_drive_file_outlined),
              border: const OutlineInputBorder(),
            ),
            validator: (value) => (value == null || value.trim().isEmpty)
                ? localizations.localFilePathErrorEmpty
                : null,
          ),
          if (onChangeDirectory != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onChangeDirectory,
              icon: const Icon(Icons.folder_open_outlined),
              label: Text(localizations.actionChangeDirectory),
            ),
          ],
          if (previewPath != null) ...[
            const SizedBox(height: 12),
            _ResolvedPathPreview(
              label: localizations.resolvedLocalPathLabel,
              value: previewPath,
            ),
          ],
        ],
      ),
    );
  }
}

/// Card for enabling or disabling foreground location determination.
class _LocationSelectionCard extends StatelessWidget {
  /// Creates a [_LocationSelectionCard].
  const _LocationSelectionCard({
    required this.locationEnabled,
    required this.onLocationEnabledChanged,
  });

  /// Whether foreground location determination is currently enabled.
  final bool locationEnabled;

  /// Callback invoked when the user toggles location determination.
  final ValueChanged<bool> onLocationEnabledChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return _SettingsSectionCard(
      icon: Icons.location_on_outlined,
      title: localizations.locationSectionTitle,
      description: localizations.locationSectionDescription,
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<bool>(
          key: const ValueKey('settings_location_segmented_button'),
          segments: [
            ButtonSegment<bool>(
              value: false,
              label: Text(localizations.locationOff),
            ),
            ButtonSegment<bool>(
              value: true,
              label: Text(localizations.locationOn),
            ),
          ],
          selected: <bool>{locationEnabled},
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) {
              onLocationEnabledChanged(selection.first);
            }
          },
        ),
      ),
    );
  }
}

/// Monospace preview box displaying a resolved local file path or WebDAV endpoint URI.
class _ResolvedPathPreview extends StatelessWidget {
  /// Creates a [_ResolvedPathPreview].
  const _ResolvedPathPreview({required this.label, required this.value});

  /// Descriptive header label above the resolved path or URI.
  final String label;

  /// Resolved path or URI string.
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}

/// Action buttons row for saving settings or testing synchronization.
class _SettingsActionRow extends StatelessWidget {
  /// Creates a [_SettingsActionRow].
  const _SettingsActionRow({
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: isTesting ? null : onSaveOnly,
              icon: const Icon(Icons.save_outlined),
              label: Text(localizations.actionSave),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: (canTestConnection && !isTesting)
                  ? onTestAndSync
                  : null,
              icon: isTesting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(localizations.actionTestConnectionAndSync),
            ),
          ),
        ],
      ),
    );
  }
}

/// WebDAV connection text fields and remote file path input.
class _SettingsFormFields extends StatelessWidget {
  /// Creates [_SettingsFormFields].
  const _SettingsFormFields({
    required this.serverUrlController,
    required this.usernameController,
    required this.passwordController,
    required this.filePathController,
    required this.obscurePassword,
    required this.onToggleObscurePassword,
  });

  /// Controller for the remote Markdown file path field.
  final TextEditingController filePathController;

  /// Whether the password input is obscured.
  final bool obscurePassword;

  /// Callback to toggle password visibility.
  final VoidCallback onToggleObscurePassword;

  /// Controller for the password field.
  final TextEditingController passwordController;

  /// Controller for the server URL field.
  final TextEditingController serverUrlController;

  /// Controller for the username field.
  final TextEditingController usernameController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WebDavCredentialsFields(
          serverUrlController: serverUrlController,
          usernameController: usernameController,
          passwordController: passwordController,
          obscurePassword: obscurePassword,
          onToggleObscurePassword: onToggleObscurePassword,
        ),
        const SizedBox(height: 16),
        ClearableTextField(
          useFormField: true,
          controller: filePathController,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: localizations.filePathLabel,
            hintText: localizations.filePathHint,
            prefixIcon: const Icon(Icons.description_outlined),
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

/// Groups the language, theme, color palette, time zone, location, diagnostics, and storage mode preference cards on [SettingsScreen].
class _SettingsPreferenceCards extends StatelessWidget {
  /// Creates [_SettingsPreferenceCards].
  const _SettingsPreferenceCards({
    required this.config,
    required this.onDiagnosticsEnabledChanged,
    required this.onLanguageChanged,
    required this.onLocationEnabledChanged,
    required this.onThemeModeChanged,
    required this.onThemePaletteChanged,
    required this.onTimeZoneModeChanged,
    required this.onManualTimeZoneOffsetChanged,
    required this.onStorageModeChanged,
  });

  /// Current [WebDavConfig] holding the selected preference states.
  final WebDavConfig config;

  /// Callback when `diagnosticsEnabled` changes.
  final ValueChanged<bool> onDiagnosticsEnabledChanged;

  /// Callback when [AppLanguage] changes.
  final ValueChanged<AppLanguage> onLanguageChanged;

  /// Callback when `locationEnabled` changes.
  final ValueChanged<bool> onLocationEnabledChanged;

  /// Callback when the manual UTC offset in minutes changes.
  final ValueChanged<int> onManualTimeZoneOffsetChanged;

  /// Callback when [StorageMode] changes.
  final ValueChanged<StorageMode> onStorageModeChanged;

  /// Callback when [AppThemeMode] changes.
  final ValueChanged<AppThemeMode> onThemeModeChanged;

  /// Callback when [AppThemePalette] changes.
  final ValueChanged<AppThemePalette> onThemePaletteChanged;

  /// Callback when [AppTimeZoneMode] changes.
  final ValueChanged<AppTimeZoneMode> onTimeZoneModeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LanguageSelectionCard(
          selectedLanguage: config.language,
          onLanguageChanged: onLanguageChanged,
        ),
        const SizedBox(height: 10),
        _ThemeSelectionCard(
          selectedThemeMode: config.themeMode,
          onThemeModeChanged: onThemeModeChanged,
        ),
        const SizedBox(height: 10),
        _ThemePaletteSelectionCard(
          selectedThemePalette: config.themePalette,
          onThemePaletteChanged: onThemePaletteChanged,
        ),
        const SizedBox(height: 10),
        _TimeZoneSelectionCard(
          selectedTimeZoneMode: config.timeZoneMode,
          manualOffsetMinutes: config.manualTimeZoneOffsetMinutes,
          onTimeZoneModeChanged: onTimeZoneModeChanged,
          onManualOffsetChanged: onManualTimeZoneOffsetChanged,
        ),
        const SizedBox(height: 10),
        _LocationSelectionCard(
          locationEnabled: config.locationEnabled,
          onLocationEnabledChanged: onLocationEnabledChanged,
        ),
        const SizedBox(height: 10),
        _DiagnosticsSelectionCard(
          diagnosticsEnabled: config.diagnosticsEnabled,
          onDiagnosticsEnabledChanged: onDiagnosticsEnabledChanged,
        ),
        const SizedBox(height: 10),
        _StorageModeSelectionCard(
          selectedStorageMode: config.storageMode,
          onStorageModeChanged: onStorageModeChanged,
        ),
      ],
    );
  }
}

/// State for [SettingsScreen].
class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Timer? _bannerTimer;
  String? _customDirectoryPath;
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _filePathController;
  late final TextEditingController _localFilePathController;
  late final TextEditingController _passwordController;
  late final TextEditingController _serverUrlController;
  late final TextEditingController _usernameController;

  bool _initialized = false;
  bool _isBannerVisible = false;
  bool _isTesting = false;
  int _manualTimeZoneOffsetMinutes = 0;
  bool _obscurePassword = true;
  bool _selectedDiagnosticsEnabled = false;
  AppLanguage _selectedLanguage = AppLanguage.system;
  bool _selectedLocationEnabled = false;
  StorageMode _selectedStorageMode = StorageMode.local;
  AppThemeMode _selectedThemeMode = AppThemeMode.system;
  AppThemePalette _selectedThemePalette = AppThemePalette.slate;
  AppTimeZoneMode _selectedTimeZoneMode = AppTimeZoneMode.automatic;
  String? _statusBannerMessage;
  _StatusBannerTone _statusTone = _StatusBannerTone.success;

  @override
  void initState() {
    super.initState();
    _serverUrlController = TextEditingController();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _filePathController = TextEditingController(
      text: WebDavConfig.defaultFileName,
    );
    _localFilePathController = TextEditingController(
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
    _localFilePathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(webDavConfigProvider);
    if (configAsync.asData?.value case final loadedConfig?) {
      _populateFieldsIfNeeded(loadedConfig);
    }
    final localizations = AppLocalizations.of(context);
    final currentConfig = _buildCurrentConfig();
    final bannerMessage = _statusBannerMessage;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: Text(localizations.settingsTitle)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          onChanged: _handleFormChanged,
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
                      _SettingsStatusBanner(
                        isVisible: _isBannerVisible,
                        message: bannerMessage,
                        onFadeOutComplete: _handleStatusBannerFadeEnd,
                        tone: _statusTone,
                      ),
                  ],
                ),
              ),
              _SettingsActionRow(
                canTestConnection: _selectedStorageMode.usesWebDav,
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

  /// Starts fading out the active status banner after the display timer expires.
  void _beginStatusBannerFadeOut() {
    if (!mounted) {
      return;
    }
    setState(() {
      _isBannerVisible = false;
    });
  }

  /// Constructs a [WebDavConfig] from the current form field values.
  WebDavConfig _buildCurrentConfig({String? directoryOverride}) {
    final rawLocalInput = _localFilePathController.text.trim().isEmpty
        ? WebDavConfig.defaultFileName
        : _localFilePathController.text.trim();
    final effectiveDir = directoryOverride ?? _customDirectoryPath;
    final hasExplicitPath =
        rawLocalInput.contains('/') || rawLocalInput.contains(r'\');
    final resolvedLocalFilePath = (effectiveDir != null && !hasExplicitPath)
        ? LocalFileRepository.combineDirectoryAndFileName(
            effectiveDir,
            rawLocalInput,
          )
        : rawLocalInput;

    return WebDavConfig(
      serverUrl: _serverUrlController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      filePath: _filePathController.text.trim().isEmpty
          ? WebDavConfig.defaultFileName
          : _filePathController.text.trim(),
      localFilePath: resolvedLocalFilePath,
      storageMode: _selectedStorageMode,
      language: _selectedLanguage,
      themeMode: _selectedThemeMode,
      themePalette: _selectedThemePalette,
      timeZoneMode: _selectedTimeZoneMode,
      manualTimeZoneOffsetMinutes: _manualTimeZoneOffsetMinutes,
      locationEnabled: _selectedLocationEnabled,
      diagnosticsEnabled: _selectedDiagnosticsEnabled,
    );
  }

  /// Builds the scrollable preference and storage section card column for [currentConfig].
  Widget _buildFormColumn(WebDavConfig currentConfig) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsPreferenceCards(
          config: currentConfig,
          onDiagnosticsEnabledChanged: _handleDiagnosticsEnabledChanged,
          onLanguageChanged: _handleLanguageChanged,
          onLocationEnabledChanged: _handleLocationEnabledChanged,
          onThemeModeChanged: _handleThemeModeChanged,
          onThemePaletteChanged: _handleThemePaletteChanged,
          onTimeZoneModeChanged: _handleTimeZoneModeChanged,
          onManualTimeZoneOffsetChanged: _handleManualTimeZoneOffsetChanged,
          onStorageModeChanged: _handleStorageModeChanged,
        ),
        if (_selectedStorageMode.usesLocal) ...[
          const SizedBox(height: 10),
          _LocalStorageSection(
            localFilePathController: _localFilePathController,
            resolvedLocalPath: _resolvePreviewLocalPath(currentConfig),
            onChangeDirectory: ref.watch(supportsDirectoryPickerProvider)
                ? _handleChangeDirectory
                : null,
          ),
        ],
        if (_selectedStorageMode.usesWebDav) ...[
          const SizedBox(height: 10),
          _WebDavStorageSection(
            serverUrlController: _serverUrlController,
            usernameController: _usernameController,
            passwordController: _passwordController,
            filePathController: _filePathController,
            obscurePassword: _obscurePassword,
            resolvedUri: currentConfig.resolveEndpointUri(),
            onToggleObscurePassword: _toggleObscurePassword,
          ),
        ],
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

  /// Runs [TaskNotifier.testConnectionAndSync] for [config] and updates the status banner.
  Future<void> _executeConnectionTest(WebDavConfig config) async {
    setState(() {
      _isTesting = true;
    });

    try {
      await ref
          .read(taskNotifierProvider.notifier)
          .testConnectionAndSync(config);
      if (!mounted) {
        return;
      }
      final localizations = AppLocalizations.of(context);
      _isTesting = false;
      _showStatusBanner(
        localizations.connectionSuccessBanner,
        _StatusBannerTone.success,
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      _isTesting = false;
      _showStatusBanner(error.toString(), _StatusBannerTone.error);
    }
  }

  /// Opens the native directory picker, moves the `.tdf` file to the chosen directory, and updates state or displays an error.
  Future<void> _handleChangeDirectory() async {
    setState(_clearStatusBanner);
    final currentConfig = _buildCurrentConfig();
    final baseDirectoryPath = ref.read(localStorageDirectoryPathProvider);
    final currentDirectory = LocalFileRepository(
      config: currentConfig,
      baseDirectoryPath: baseDirectoryPath,
    ).tryResolveDirectoryPath();
    final selectedDirectory = await ref.read(directoryPickerProvider)(
      initialDirectory: currentDirectory,
    );
    if (!mounted ||
        selectedDirectory == null ||
        selectedDirectory.trim().isEmpty ||
        selectedDirectory == currentDirectory) {
      return;
    }
    final candidateConfig = _buildCurrentConfig(
      directoryOverride: selectedDirectory,
    );
    try {
      await ref
          .read(webDavConfigProvider.notifier)
          .changeLocalFileLocation(candidateConfig);
      if (!mounted) {
        return;
      }
      final localizations = AppLocalizations.of(context);
      setState(() {
        _customDirectoryPath = selectedDirectory;
      });
      _showStatusBanner(
        localizations.localDirectoryMovedBanner,
        _StatusBannerTone.success,
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      _showStatusBanner(error.toString(), _StatusBannerTone.error);
    }
  }

  /// Updates [_selectedDiagnosticsEnabled], synchronizes [AppLogger], and persists it immediately.
  Future<void> _handleDiagnosticsEnabledChanged(bool diagnosticsEnabled) async {
    setState(() {
      _selectedDiagnosticsEnabled = diagnosticsEnabled;
      _clearStatusBanner();
    });
    await ref
        .read(webDavConfigProvider.notifier)
        .updateDiagnosticsEnabled(diagnosticsEnabled);
  }

  /// Clears stale status banners and refreshes previews when form inputs change.
  void _handleFormChanged() {
    setState(_clearStatusBanner);
  }

  /// Updates the selected [AppLanguage] and persists it immediately.
  Future<void> _handleLanguageChanged(AppLanguage newLanguage) async {
    setState(() {
      _selectedLanguage = newLanguage;
      _clearStatusBanner();
    });
    await ref.read(webDavConfigProvider.notifier).updateLanguage(newLanguage);
  }

  /// Updates [_selectedLocationEnabled] and persists it immediately.
  Future<void> _handleLocationEnabledChanged(bool locationEnabled) async {
    setState(() {
      _selectedLocationEnabled = locationEnabled;
      _clearStatusBanner();
    });
    await ref
        .read(webDavConfigProvider.notifier)
        .updateLocationEnabled(locationEnabled);
  }

  /// Updates [_manualTimeZoneOffsetMinutes] and persists it immediately.
  Future<void> _handleManualTimeZoneOffsetChanged(int newOffsetMinutes) async {
    setState(() {
      _manualTimeZoneOffsetMinutes = newOffsetMinutes;
      _clearStatusBanner();
    });
    await ref
        .read(webDavConfigProvider.notifier)
        .updateManualTimeZoneOffsetMinutes(newOffsetMinutes);
  }

  /// Removes the status banner from the widget tree once its fade-out animation finishes.
  void _handleStatusBannerFadeEnd() {
    if (!mounted || _isBannerVisible) {
      return;
    }
    setState(() {
      _statusBannerMessage = null;
    });
  }

  /// Updates the selected [StorageMode] and persists it immediately.
  Future<void> _handleStorageModeChanged(StorageMode newStorageMode) async {
    setState(() {
      _selectedStorageMode = newStorageMode;
      _clearStatusBanner();
    });
    await ref
        .read(webDavConfigProvider.notifier)
        .updateStorageMode(newStorageMode);
  }

  /// Updates the selected [AppThemeMode] and persists it immediately.
  Future<void> _handleThemeModeChanged(AppThemeMode newThemeMode) async {
    setState(() {
      _selectedThemeMode = newThemeMode;
    });
    await ref.read(webDavConfigProvider.notifier).updateThemeMode(newThemeMode);
  }

  /// Updates the selected [AppThemePalette] and persists it immediately.
  Future<void> _handleThemePaletteChanged(
    AppThemePalette newThemePalette,
  ) async {
    setState(() {
      _selectedThemePalette = newThemePalette;
    });
    await ref
        .read(webDavConfigProvider.notifier)
        .updateThemePalette(newThemePalette);
  }

  /// Updates the selected [AppTimeZoneMode] and persists it immediately.
  Future<void> _handleTimeZoneModeChanged(
    AppTimeZoneMode newTimeZoneMode,
  ) async {
    setState(() {
      _selectedTimeZoneMode = newTimeZoneMode;
      _clearStatusBanner();
    });
    await ref
        .read(webDavConfigProvider.notifier)
        .updateTimeZoneMode(newTimeZoneMode);
  }

  /// Initializes the text controllers and selections once when [config] finishes loading.
  void _populateFieldsIfNeeded(WebDavConfig config) {
    _selectedLanguage = config.language;
    _selectedThemeMode = config.themeMode;
    _selectedThemePalette = config.themePalette;
    _selectedTimeZoneMode = config.timeZoneMode;
    _manualTimeZoneOffsetMinutes = config.manualTimeZoneOffsetMinutes;
    _selectedLocationEnabled = config.locationEnabled;
    _selectedDiagnosticsEnabled = config.diagnosticsEnabled;
    _selectedStorageMode = config.storageMode;
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
    final rawLocal = config.localFilePath.trim();
    if (rawLocal.contains('/') || rawLocal.contains(r'\')) {
      final baseDirectoryPath = ref.read(localStorageDirectoryPathProvider);
      _customDirectoryPath = LocalFileRepository(
        config: config,
        baseDirectoryPath: baseDirectoryPath,
      ).tryResolveDirectoryPath();
      _localFilePathController.text =
          LocalFileRepository.extractFileNameFromPath(rawLocal);
    } else {
      _localFilePathController.text = rawLocal.isEmpty
          ? WebDavConfig.defaultFileName
          : rawLocal;
    }
  }

  /// Resolves the preview local file path for [config], or `null` if invalid.
  String? _resolvePreviewLocalPath(WebDavConfig config) {
    if (_localFilePathController.text.trim().isEmpty) {
      return null;
    }
    final baseDirectoryPath = ref.read(localStorageDirectoryPathProvider);
    return LocalFileRepository(
      config: config,
      baseDirectoryPath: baseDirectoryPath,
    ).tryResolveFilePath();
  }

  /// Validates and persists the current settings without triggering a remote sync.
  Future<void> _saveOnly() async {
    setState(_clearStatusBanner);
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final config = _buildCurrentConfig();
    try {
      await ref
          .read(webDavConfigProvider.notifier)
          .changeLocalFileLocation(config);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      _showStatusBanner(error.toString(), _StatusBannerTone.error);
      return;
    }
    if (!mounted) {
      return;
    }
    final localizations = AppLocalizations.of(context);
    _showStatusBanner(
      localizations.credentialsSavedBanner,
      _StatusBannerTone.success,
    );
  }

  /// Displays [message] with [tone] and schedules an automatic fade-out.
  void _showStatusBanner(String message, _StatusBannerTone tone) {
    _bannerTimer?.cancel();
    setState(() {
      _statusTone = tone;
      _statusBannerMessage = message;
      _isBannerVisible = true;
    });
    _bannerTimer = Timer(
      SettingsScreen.statusBannerDisplayDuration,
      _beginStatusBannerFadeOut,
    );
  }

  /// Validates the form, saves [WebDavConfig], and runs a storage synchronization test.
  Future<void> _testConnectionAndSync() async {
    setState(_clearStatusBanner);
    if (!_selectedStorageMode.usesWebDav) {
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final config = _buildCurrentConfig();
    if (!config.isWebDavConfigured) {
      final localizations = AppLocalizations.of(context);
      _showStatusBanner(
        localizations.errorWebDavNotConfigured,
        _StatusBannerTone.error,
      );
      return;
    }
    await _executeConnectionTest(config);
  }

  /// Toggles [_obscurePassword] visibility.
  void _toggleObscurePassword() {
    setState(() {
      _obscurePassword = !_obscurePassword;
    });
  }
}

/// Shared Material 3 card container with an icon, title, description, and body [child].
class _SettingsSectionCard extends StatelessWidget {
  /// Creates a [_SettingsSectionCard].
  const _SettingsSectionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
  });

  /// Interactive content below the description.
  final Widget child;

  /// Section subtitle description.
  final String description;

  /// Leading header icon.
  final IconData icon;

  /// Section title text.
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      color: theme.cardColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

/// Floating status banner displaying save confirmation or synchronization messages above the bottom action row.
class _SettingsStatusBanner extends StatelessWidget {
  /// Creates a [_SettingsStatusBanner].
  const _SettingsStatusBanner({
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
  final _StatusBannerTone tone;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isError = tone == _StatusBannerTone.error;
    final foregroundColor = isError
        ? colorScheme.onErrorContainer
        : colorScheme.onPrimaryContainer;

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
              children: [
                Icon(
                  isError
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  color: foregroundColor,
                ),
                const SizedBox(width: 10),
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

/// Visual tone for [_SettingsStatusBanner].
enum _StatusBannerTone { success, error }

/// Card for choosing the Markdown storage mode (`Local`, `WebDAV`, or `Both`).
class _StorageModeSelectionCard extends StatelessWidget {
  /// Creates a [_StorageModeSelectionCard].
  const _StorageModeSelectionCard({
    required this.selectedStorageMode,
    required this.onStorageModeChanged,
  });

  /// Callback invoked when the user selects a new [StorageMode].
  final ValueChanged<StorageMode> onStorageModeChanged;

  /// Currently selected [StorageMode].
  final StorageMode selectedStorageMode;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return _SettingsSectionCard(
      icon: Icons.storage_rounded,
      title: localizations.storageModeSectionTitle,
      description: localizations.storageModeSectionDescription,
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<StorageMode>(
          segments: [
            ButtonSegment(
              value: StorageMode.local,
              label: Text(localizations.storageModeLocal),
            ),
            ButtonSegment(
              value: StorageMode.webdav,
              label: Text(localizations.storageModeWebDav),
            ),
            ButtonSegment(
              value: StorageMode.both,
              label: Text(localizations.storageModeBoth),
            ),
          ],
          selected: {selectedStorageMode},
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) {
              onStorageModeChanged(selection.first);
            }
          },
        ),
      ),
    );
  }
}

/// Card for choosing the Material 3 color palette (`Slate` or `Navy`).
class _ThemePaletteSelectionCard extends StatelessWidget {
  /// Creates a [_ThemePaletteSelectionCard].
  const _ThemePaletteSelectionCard({
    required this.selectedThemePalette,
    required this.onThemePaletteChanged,
  });

  /// Callback invoked when the user selects a new [AppThemePalette].
  final ValueChanged<AppThemePalette> onThemePaletteChanged;

  /// Currently selected [AppThemePalette].
  final AppThemePalette selectedThemePalette;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return _SettingsSectionCard(
      icon: Icons.palette_outlined,
      title: localizations.themePaletteSectionTitle,
      description: localizations.themePaletteSectionDescription,
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<AppThemePalette>(
          segments: [
            ButtonSegment(
              value: AppThemePalette.slate,
              label: Text(localizations.themePaletteSlate),
            ),
            ButtonSegment(
              value: AppThemePalette.navy,
              label: Text(localizations.themePaletteNavy),
            ),
          ],
          selected: {selectedThemePalette},
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) {
              onThemePaletteChanged(selection.first);
            }
          },
        ),
      ),
    );
  }
}

/// Card for choosing the application color theme (`System`, `Light`, or `Dark`).
class _ThemeSelectionCard extends StatelessWidget {
  /// Creates a [_ThemeSelectionCard].
  const _ThemeSelectionCard({
    required this.selectedThemeMode,
    required this.onThemeModeChanged,
  });

  /// Callback invoked when the user selects a new [AppThemeMode].
  final ValueChanged<AppThemeMode> onThemeModeChanged;

  /// Currently selected [AppThemeMode].
  final AppThemeMode selectedThemeMode;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return _SettingsSectionCard(
      icon: Icons.brightness_6_outlined,
      title: localizations.themeSectionTitle,
      description: localizations.themeSectionDescription,
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<AppThemeMode>(
          segments: [
            ButtonSegment(
              value: AppThemeMode.system,
              label: Text(localizations.themeSystem),
            ),
            ButtonSegment(
              value: AppThemeMode.light,
              label: Text(localizations.themeLight),
            ),
            ButtonSegment(
              value: AppThemeMode.dark,
              label: Text(localizations.themeDark),
            ),
          ],
          selected: {selectedThemeMode},
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) {
              onThemeModeChanged(selection.first);
            }
          },
        ),
      ),
    );
  }
}

/// Card for choosing whether the local time zone is detected automatically or configured manually.
class _TimeZoneSelectionCard extends StatelessWidget {
  /// Creates a [_TimeZoneSelectionCard].
  const _TimeZoneSelectionCard({
    required this.selectedTimeZoneMode,
    required this.manualOffsetMinutes,
    required this.onTimeZoneModeChanged,
    required this.onManualOffsetChanged,
  });

  /// Currently selected manual UTC offset in minutes.
  final int manualOffsetMinutes;

  /// Callback invoked when the user selects a manual UTC offset.
  final ValueChanged<int> onManualOffsetChanged;

  /// Callback invoked when the user selects a new [AppTimeZoneMode].
  final ValueChanged<AppTimeZoneMode> onTimeZoneModeChanged;

  /// Currently selected [AppTimeZoneMode].
  final AppTimeZoneMode selectedTimeZoneMode;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final effectiveOffset =
        WebDavConfig.supportedUtcOffsetMinutes.contains(manualOffsetMinutes)
        ? manualOffsetMinutes
        : 0;

    return _SettingsSectionCard(
      icon: Icons.schedule_rounded,
      title: localizations.timeZoneSectionTitle,
      description: localizations.timeZoneSectionDescription,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<AppTimeZoneMode>(
              segments: [
                ButtonSegment(
                  value: AppTimeZoneMode.automatic,
                  label: Text(localizations.timeZoneModeAutomatic),
                ),
                ButtonSegment(
                  value: AppTimeZoneMode.manual,
                  label: Text(localizations.timeZoneModeManual),
                ),
              ],
              selected: {selectedTimeZoneMode},
              onSelectionChanged: (selection) {
                if (selection.isNotEmpty) {
                  onTimeZoneModeChanged(selection.first);
                }
              },
            ),
          ),
          if (selectedTimeZoneMode == AppTimeZoneMode.manual) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: effectiveOffset,
              decoration: InputDecoration(
                labelText: localizations.timeZoneOffsetLabel,
                prefixIcon: const Icon(Icons.public_rounded),
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final offset in WebDavConfig.supportedUtcOffsetMinutes)
                  DropdownMenuItem<int>(
                    value: offset,
                    child: Text(WebDavConfig.formatUtcOffset(offset)),
                  ),
              ],
              onChanged: (selected) {
                if (selected != null) {
                  onManualOffsetChanged(selected);
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Server URL, username, and password input fields for WebDAV authentication.
class _WebDavCredentialsFields extends StatelessWidget {
  /// Creates [_WebDavCredentialsFields].
  const _WebDavCredentialsFields({
    required this.serverUrlController,
    required this.usernameController,
    required this.passwordController,
    required this.obscurePassword,
    required this.onToggleObscurePassword,
  });

  /// Whether the password input is obscured.
  final bool obscurePassword;

  /// Callback to toggle password visibility.
  final VoidCallback onToggleObscurePassword;

  /// Controller for the password field.
  final TextEditingController passwordController;

  /// Controller for the server URL field.
  final TextEditingController serverUrlController;

  /// Controller for the username field.
  final TextEditingController usernameController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClearableTextField(
          useFormField: true,
          controller: serverUrlController,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: localizations.serverUrlLabel,
            hintText: 'https://cloud.example.com',
            prefixIcon: const Icon(Icons.dns_outlined),
            border: const OutlineInputBorder(),
          ),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? localizations.serverUrlErrorEmpty
              : null,
        ),
        const SizedBox(height: 16),
        ClearableTextField(
          useFormField: true,
          controller: usernameController,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: localizations.usernameLabel,
            hintText: 'example-user',
            prefixIcon: const Icon(Icons.person_outline_rounded),
            border: const OutlineInputBorder(),
          ),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? localizations.usernameErrorEmpty
              : null,
        ),
        const SizedBox(height: 16),
        _WebDavPasswordField(
          controller: passwordController,
          obscurePassword: obscurePassword,
          onToggleObscurePassword: onToggleObscurePassword,
        ),
      ],
    );
  }
}

/// Password text field with a visibility toggle button for WebDAV authentication.
class _WebDavPasswordField extends StatelessWidget {
  /// Creates a [_WebDavPasswordField].
  const _WebDavPasswordField({
    required this.controller,
    required this.obscurePassword,
    required this.onToggleObscurePassword,
  });

  /// Controller for the password input.
  final TextEditingController controller;

  /// Whether the password text is obscured.
  final bool obscurePassword;

  /// Callback to toggle password visibility.
  final VoidCallback onToggleObscurePassword;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return ClearableTextField(
      useFormField: true,
      controller: controller,
      obscureText: obscurePassword,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: localizations.passwordLabel,
        prefixIcon: const Icon(Icons.key_outlined),
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: obscurePassword
              ? localizations.tooltipShowPassword
              : localizations.tooltipHidePassword,
          icon: Icon(
            obscurePassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
          onPressed: onToggleObscurePassword,
        ),
      ),
      validator: (value) => (value == null || value.isEmpty)
          ? localizations.passwordErrorEmpty
          : null,
    );
  }
}

/// Card grouping the WebDAV synchronization header, connection form fields, and resolved URI preview.
class _WebDavStorageSection extends StatelessWidget {
  /// Creates a [_WebDavStorageSection].
  const _WebDavStorageSection({
    required this.serverUrlController,
    required this.usernameController,
    required this.passwordController,
    required this.filePathController,
    required this.obscurePassword,
    required this.resolvedUri,
    required this.onToggleObscurePassword,
  });

  /// Controller for the remote Markdown file path field.
  final TextEditingController filePathController;

  /// Whether the password input is obscured.
  final bool obscurePassword;

  /// Callback to toggle password visibility.
  final VoidCallback onToggleObscurePassword;

  /// Controller for the password field.
  final TextEditingController passwordController;

  /// Resolved WebDAV endpoint URI preview, or `null` if empty.
  final Uri? resolvedUri;

  /// Controller for the server URL field.
  final TextEditingController serverUrlController;

  /// Controller for the username field.
  final TextEditingController usernameController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final endpointUri = resolvedUri;

    return _SettingsSectionCard(
      icon: Icons.cloud_sync_outlined,
      title: localizations.webdavSectionTitle,
      description: localizations.webdavSectionDescription,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsFormFields(
            serverUrlController: serverUrlController,
            usernameController: usernameController,
            passwordController: passwordController,
            filePathController: filePathController,
            obscurePassword: obscurePassword,
            onToggleObscurePassword: onToggleObscurePassword,
          ),
          if (endpointUri != null) ...[
            const SizedBox(height: 12),
            _ResolvedPathPreview(
              label: localizations.resolvedEndpointLabel,
              value: endpointUri.toString(),
            ),
          ],
        ],
      ),
    );
  }
}
