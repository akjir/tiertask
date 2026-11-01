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

/// Reusable row of preset `.tdf` filename [ActionChip]s (`tiertask.tdf` and `t2.tdf`).
class _FileNamePresetChips extends StatelessWidget {
  /// Creates [_FileNamePresetChips].
  const _FileNamePresetChips({required this.onSelectFileName});

  /// Callback invoked with the selected preset file name.
  final ValueChanged<String> onSelectFileName;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        ActionChip(
          label: const Text('tiertask.tdf'),
          onPressed: () => onSelectFileName('tiertask.tdf'),
        ),
        ActionChip(
          label: const Text('t2.tdf'),
          onPressed: () => onSelectFileName('t2.tdf'),
        ),
      ],
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
    required this.onSelectFileName,
  });

  /// Controller for the local Markdown file name or path field.
  final TextEditingController localFilePathController;

  /// Callback invoked when a preset file name chip is selected.
  final ValueChanged<String> onSelectFileName;

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
          TextFormField(
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
          const SizedBox(height: 8),
          _FileNamePresetChips(onSelectFileName: onSelectFileName),
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

/// Card for choosing whether the total open task count is shown on label cards.
class _OpenTaskCountSelectionCard extends StatelessWidget {
  /// Creates an [_OpenTaskCountSelectionCard].
  const _OpenTaskCountSelectionCard({
    required this.showOpenTaskCount,
    required this.onShowOpenTaskCountChanged,
  });

  /// Callback invoked when the user toggles open task count visibility.
  final ValueChanged<bool> onShowOpenTaskCountChanged;

  /// Whether the open task count is currently shown.
  final bool showOpenTaskCount;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return _SettingsSectionCard(
      icon: Icons.numbers_rounded,
      title: localizations.openTaskCountSectionTitle,
      description: localizations.openTaskCountSectionDescription,
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<bool>(
          segments: [
            ButtonSegment(
              value: false,
              label: Text(localizations.openTaskCountOff),
            ),
            ButtonSegment(
              value: true,
              label: Text(localizations.openTaskCountOn),
            ),
          ],
          selected: {showOpenTaskCount},
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) {
              onShowOpenTaskCountChanged(selection.first);
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

    return Row(
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
            onPressed: (canTestConnection && !isTesting) ? onTestAndSync : null,
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
    );
  }
}

/// WebDAV connection text fields and filename quick-select chips.
class _SettingsFormFields extends StatelessWidget {
  /// Creates [_SettingsFormFields].
  const _SettingsFormFields({
    required this.serverUrlController,
    required this.usernameController,
    required this.passwordController,
    required this.filePathController,
    required this.obscurePassword,
    required this.onToggleObscurePassword,
    required this.onSelectFileName,
  });

  /// Controller for the remote Markdown file path field.
  final TextEditingController filePathController;

  /// Whether the password input is obscured.
  final bool obscurePassword;

  /// Callback when a preset filename chip is tapped.
  final ValueChanged<String> onSelectFileName;

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
        TextFormField(
          controller: filePathController,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: localizations.filePathLabel,
            hintText: localizations.filePathHint,
            prefixIcon: const Icon(Icons.description_outlined),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        _FileNamePresetChips(onSelectFileName: onSelectFileName),
      ],
    );
  }
}

/// Groups the language, theme, open task count, and storage mode preference cards on [SettingsScreen].
class _SettingsPreferenceCards extends StatelessWidget {
  /// Creates [_SettingsPreferenceCards].
  const _SettingsPreferenceCards({
    required this.selectedLanguage,
    required this.selectedThemeMode,
    required this.showOpenTaskCount,
    required this.selectedStorageMode,
    required this.onLanguageChanged,
    required this.onThemeModeChanged,
    required this.onShowOpenTaskCountChanged,
    required this.onStorageModeChanged,
  });

  /// Callback when [AppLanguage] changes.
  final ValueChanged<AppLanguage> onLanguageChanged;

  /// Callback when open task count visibility changes.
  final ValueChanged<bool> onShowOpenTaskCountChanged;

  /// Callback when [StorageMode] changes.
  final ValueChanged<StorageMode> onStorageModeChanged;

  /// Callback when [AppThemeMode] changes.
  final ValueChanged<AppThemeMode> onThemeModeChanged;

  /// Currently selected display language.
  final AppLanguage selectedLanguage;

  /// Currently selected storage mode.
  final StorageMode selectedStorageMode;

  /// Currently selected theme mode.
  final AppThemeMode selectedThemeMode;

  /// Whether the open task count is shown on category and location cards.
  final bool showOpenTaskCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LanguageSelectionCard(
          selectedLanguage: selectedLanguage,
          onLanguageChanged: onLanguageChanged,
        ),
        const SizedBox(height: 16),
        _ThemeSelectionCard(
          selectedThemeMode: selectedThemeMode,
          onThemeModeChanged: onThemeModeChanged,
        ),
        const SizedBox(height: 16),
        _OpenTaskCountSelectionCard(
          showOpenTaskCount: showOpenTaskCount,
          onShowOpenTaskCountChanged: onShowOpenTaskCountChanged,
        ),
        const SizedBox(height: 16),
        _StorageModeSelectionCard(
          selectedStorageMode: selectedStorageMode,
          onStorageModeChanged: onStorageModeChanged,
        ),
      ],
    );
  }
}

/// State for [SettingsScreen].
class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Timer? _bannerTimer;
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _filePathController;
  late final TextEditingController _localFilePathController;
  late final TextEditingController _passwordController;
  late final TextEditingController _serverUrlController;
  late final TextEditingController _usernameController;

  bool _initialized = false;
  bool _isBannerVisible = false;
  bool _isTesting = false;
  bool _obscurePassword = true;
  AppLanguage _selectedLanguage = AppLanguage.system;
  StorageMode _selectedStorageMode = StorageMode.local;
  AppThemeMode _selectedThemeMode = AppThemeMode.system;
  bool _showOpenTaskCount = false;
  String? _statusBannerMessage;
  _StatusBannerTone _statusTone = _StatusBannerTone.success;

  @override
  void initState() {
    super.initState();
    _serverUrlController = TextEditingController();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _filePathController = TextEditingController(text: 'tiertask.tdf');
    _localFilePathController = TextEditingController(text: 'tiertask.tdf');
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
      appBar: AppBar(title: Text(localizations.settingsTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          onChanged: _handleFormChanged,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SettingsPreferenceCards(
                selectedLanguage: _selectedLanguage,
                selectedThemeMode: _selectedThemeMode,
                showOpenTaskCount: _showOpenTaskCount,
                selectedStorageMode: _selectedStorageMode,
                onLanguageChanged: _handleLanguageChanged,
                onThemeModeChanged: _handleThemeModeChanged,
                onShowOpenTaskCountChanged: _handleShowOpenTaskCountChanged,
                onStorageModeChanged: _handleStorageModeChanged,
              ),
              if (_selectedStorageMode.usesLocal) ...[
                const SizedBox(height: 16),
                _LocalStorageSection(
                  localFilePathController: _localFilePathController,
                  resolvedLocalPath: _resolvePreviewLocalPath(currentConfig),
                  onSelectFileName: _selectLocalFileName,
                ),
              ],
              if (_selectedStorageMode.usesWebDav) ...[
                const SizedBox(height: 16),
                _WebDavStorageSection(
                  serverUrlController: _serverUrlController,
                  usernameController: _usernameController,
                  passwordController: _passwordController,
                  filePathController: _filePathController,
                  obscurePassword: _obscurePassword,
                  resolvedUri: currentConfig.resolveEndpointUri(),
                  onToggleObscurePassword: _toggleObscurePassword,
                  onSelectFileName: _selectRemoteFileName,
                ),
              ],
              const SizedBox(height: 20),
              if (bannerMessage != null) ...[
                _SettingsStatusBanner(
                  isVisible: _isBannerVisible,
                  message: bannerMessage,
                  onFadeOutComplete: _handleStatusBannerFadeEnd,
                  tone: _statusTone,
                ),
                const SizedBox(height: 16),
              ],
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
  WebDavConfig _buildCurrentConfig() {
    return WebDavConfig(
      serverUrl: _serverUrlController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      filePath: _filePathController.text.trim().isEmpty
          ? 'tiertask.tdf'
          : _filePathController.text.trim(),
      localFilePath: _localFilePathController.text.trim().isEmpty
          ? 'tiertask.tdf'
          : _localFilePathController.text.trim(),
      storageMode: _selectedStorageMode,
      language: _selectedLanguage,
      themeMode: _selectedThemeMode,
      showOpenTaskCount: _showOpenTaskCount,
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

  /// Updates [_showOpenTaskCount] and persists the preference immediately.
  Future<void> _handleShowOpenTaskCountChanged(bool showOpenTaskCount) async {
    setState(() {
      _showOpenTaskCount = showOpenTaskCount;
      _clearStatusBanner();
    });
    await ref
        .read(webDavConfigProvider.notifier)
        .updateShowOpenTaskCount(showOpenTaskCount);
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

  /// Initializes the text controllers and selections once when [config] finishes loading.
  void _populateFieldsIfNeeded(WebDavConfig config) {
    _selectedLanguage = config.language;
    _selectedThemeMode = config.themeMode;
    _showOpenTaskCount = config.showOpenTaskCount;
    _selectedStorageMode = config.storageMode;
    if (_initialized) {
      return;
    }
    _initialized = true;
    _serverUrlController.text = config.serverUrl;
    _usernameController.text = config.username;
    _passwordController.text = config.password;
    _filePathController.text = config.filePath.isEmpty
        ? 'tiertask.tdf'
        : config.filePath;
    _localFilePathController.text = config.localFilePath.isEmpty
        ? 'tiertask.tdf'
        : config.localFilePath;
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
    await ref.read(webDavConfigProvider.notifier).updateConfig(config);
    if (!mounted) {
      return;
    }
    final localizations = AppLocalizations.of(context);
    _showStatusBanner(
      localizations.credentialsSavedBanner,
      _StatusBannerTone.success,
    );
  }

  /// Sets [_localFilePathController] to [name] and clears stale status banners.
  void _selectLocalFileName(String name) {
    setState(() {
      _localFilePathController.text = name;
      _clearStatusBanner();
    });
  }

  /// Sets [_filePathController] to [name] and clears stale status banners.
  void _selectRemoteFileName(String name) {
    setState(() {
      _filePathController.text = name;
      _clearStatusBanner();
    });
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

/// Shared Material 3 card container with an icon, title, description, and optional body [child].
class _SettingsSectionCard extends StatelessWidget {
  /// Creates a [_SettingsSectionCard].
  const _SettingsSectionCard({
    required this.icon,
    required this.title,
    required this.description,
    this.child,
  });

  /// Optional interactive content below the description.
  final Widget? child;

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
    final bodyChild = child;

    return Card(
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
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
            const SizedBox(height: 8),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (bodyChild != null) ...[const SizedBox(height: 12), bodyChild],
          ],
        ),
      ),
    );
  }
}

/// Status banner displaying save confirmation or synchronization messages that fade out.
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

    return AnimatedOpacity(
      opacity: isVisible ? 1.0 : 0.0,
      duration: SettingsScreen.statusBannerFadeDuration,
      curve: Curves.easeOut,
      onEnd: onFadeOutComplete,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isError
              ? colorScheme.errorContainer
              : colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
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
              child: Text(message, style: TextStyle(color: foregroundColor)),
            ),
          ],
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
        TextFormField(
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
        TextFormField(
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
    return TextFormField(
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

/// Section grouping the WebDAV informational card, connection form fields, and resolved URI preview.
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
    required this.onSelectFileName,
  });

  /// Controller for the remote Markdown file path field.
  final TextEditingController filePathController;

  /// Whether the password input is obscured.
  final bool obscurePassword;

  /// Callback when a preset filename chip is tapped.
  final ValueChanged<String> onSelectFileName;

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsSectionCard(
          icon: Icons.cloud_sync_outlined,
          title: localizations.webdavSectionTitle,
          description: localizations.webdavSectionDescription,
        ),
        const SizedBox(height: 16),
        _SettingsFormFields(
          serverUrlController: serverUrlController,
          usernameController: usernameController,
          passwordController: passwordController,
          filePathController: filePathController,
          obscurePassword: obscurePassword,
          onToggleObscurePassword: onToggleObscurePassword,
          onSelectFileName: onSelectFileName,
        ),
        if (endpointUri != null) ...[
          const SizedBox(height: 12),
          _ResolvedPathPreview(
            label: localizations.resolvedEndpointLabel,
            value: endpointUri.toString(),
          ),
        ],
      ],
    );
  }
}
