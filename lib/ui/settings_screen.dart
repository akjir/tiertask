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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/webdav_config.dart';
import '../providers/task_providers.dart';

/// Settings screen for display language selection, WebDAV parameters, and connection testing.
class SettingsScreen extends ConsumerStatefulWidget {
  /// Creates a [SettingsScreen] widget.
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final localizations = AppLocalizations.of(context);

    return Card(
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.language_rounded, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  localizations.languageSectionTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              localizations.languageSectionDescription,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
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
          ],
        ),
      ),
    );
  }
}

/// Displays the resolved WebDAV GET/PUT endpoint URI preview.
class _ResolvedEndpointPreview extends StatelessWidget {
  /// Creates a [_ResolvedEndpointPreview] for [resolvedUri].
  const _ResolvedEndpointPreview({required this.resolvedUri});

  /// Resolved WebDAV endpoint URI.
  final Uri resolvedUri;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final localizations = AppLocalizations.of(context);

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
            localizations.resolvedEndpointLabel,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            resolvedUri.toString(),
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}

/// Action buttons row for saving settings or testing WebDAV synchronization.
class _SettingsActionRow extends StatelessWidget {
  /// Creates a [_SettingsActionRow].
  const _SettingsActionRow({
    required this.isTesting,
    required this.onSaveOnly,
    required this.onTestAndSync,
  });

  /// Whether a connection test is currently running.
  final bool isTesting;

  /// Callback to save credentials locally without testing.
  final VoidCallback onSaveOnly;

  /// Callback to test connection and synchronize now.
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
            onPressed: isTesting ? null : onTestAndSync,
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

  /// Controller for the Markdown file path field.
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
        TextFormField(
          controller: passwordController,
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
        Wrap(
          spacing: 8,
          children: [
            ActionChip(
              label: const Text('tiertask.md'),
              onPressed: () => onSelectFileName('tiertask.md'),
            ),
            ActionChip(
              label: const Text('t2.md'),
              onPressed: () => onSelectFileName('t2.md'),
            ),
          ],
        ),
      ],
    );
  }
}

/// State for [SettingsScreen].
class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _filePathController;
  late final TextEditingController _passwordController;
  late final TextEditingController _serverUrlController;
  late final TextEditingController _usernameController;

  bool _initialized = false;
  bool _isTesting = false;
  bool _obscurePassword = true;
  AppLanguage _selectedLanguage = AppLanguage.system;
  String? _statusBannerMessage;
  _StatusBannerTone _statusTone = _StatusBannerTone.success;

  @override
  void initState() {
    super.initState();
    _serverUrlController = TextEditingController();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _filePathController = TextEditingController(text: 'tiertask.md');
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _filePathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(webDavConfigProvider);
    if (configAsync.asData?.value case final loadedConfig?) {
      _populateFieldsIfNeeded(loadedConfig);
    }

    final localizations = AppLocalizations.of(context);
    final resolvedUri = _buildCurrentConfig().resolveEndpointUri();
    final bannerMessage = _statusBannerMessage;

    return Scaffold(
      appBar: AppBar(title: Text(localizations.settingsTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          onChanged: () => setState(() {}),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LanguageSelectionCard(
                selectedLanguage: _selectedLanguage,
                onLanguageChanged: _handleLanguageChanged,
              ),
              const SizedBox(height: 16),
              const _WebDavInfoCard(),
              const SizedBox(height: 16),
              _SettingsFormFields(
                serverUrlController: _serverUrlController,
                usernameController: _usernameController,
                passwordController: _passwordController,
                filePathController: _filePathController,
                obscurePassword: _obscurePassword,
                onToggleObscurePassword: () => setState(() {
                  _obscurePassword = !_obscurePassword;
                }),
                onSelectFileName: (name) => setState(() {
                  _filePathController.text = name;
                }),
              ),
              if (resolvedUri != null) ...[
                const SizedBox(height: 12),
                _ResolvedEndpointPreview(resolvedUri: resolvedUri),
              ],
              const SizedBox(height: 20),
              if (bannerMessage != null) ...[
                _SettingsStatusBanner(
                  message: bannerMessage,
                  tone: _statusTone,
                ),
                const SizedBox(height: 16),
              ],
              _SettingsActionRow(
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

  /// Constructs a [WebDavConfig] from the current form field values.
  WebDavConfig _buildCurrentConfig() {
    return WebDavConfig(
      serverUrl: _serverUrlController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      filePath: _filePathController.text.trim().isEmpty
          ? 'tiertask.md'
          : _filePathController.text.trim(),
      language: _selectedLanguage,
    );
  }

  /// Updates the selected [AppLanguage] and persists it immediately.
  Future<void> _handleLanguageChanged(AppLanguage newLanguage) async {
    setState(() {
      _selectedLanguage = newLanguage;
    });
    await ref.read(webDavConfigProvider.notifier).updateLanguage(newLanguage);
  }

  /// Initializes the text controllers once when [config] finishes loading.
  void _populateFieldsIfNeeded(WebDavConfig config) {
    _selectedLanguage = config.language;
    if (_initialized) {
      return;
    }
    _initialized = true;
    _serverUrlController.text = config.serverUrl;
    _usernameController.text = config.username;
    _passwordController.text = config.password;
    _filePathController.text = config.filePath.isEmpty
        ? 'tiertask.md'
        : config.filePath;
  }

  /// Validates and persists the current settings without triggering a remote sync.
  Future<void> _saveOnly() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final config = _buildCurrentConfig();
    await ref.read(webDavConfigProvider.notifier).updateConfig(config);
    if (!mounted) {
      return;
    }
    final localizations = AppLocalizations.of(context);
    setState(() {
      _statusTone = _StatusBannerTone.success;
      _statusBannerMessage = localizations.credentialsSavedBanner;
    });
  }

  /// Validates the form, saves [WebDavConfig], and runs a remote WebDAV sync test.
  Future<void> _testConnectionAndSync() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final config = _buildCurrentConfig();

    setState(() {
      _isTesting = true;
      _statusBannerMessage = null;
    });

    try {
      await ref
          .read(taskNotifierProvider.notifier)
          .testConnectionAndSync(config);
      if (!mounted) {
        return;
      }
      final localizations = AppLocalizations.of(context);
      setState(() {
        _isTesting = false;
        _statusTone = _StatusBannerTone.success;
        _statusBannerMessage = localizations.connectionSuccessBanner;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isTesting = false;
        _statusTone = _StatusBannerTone.error;
        _statusBannerMessage = error.toString();
      });
    }
  }
}

/// Status banner displaying save confirmation or synchronization errors.
class _SettingsStatusBanner extends StatelessWidget {
  /// Creates a [_SettingsStatusBanner].
  const _SettingsStatusBanner({required this.message, required this.tone});

  /// Status message text.
  final String message;

  /// Visual tone (`success` or `error`).
  final _StatusBannerTone tone;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isError = tone == _StatusBannerTone.error;

    return Container(
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
            color: isError
                ? colorScheme.onErrorContainer
                : colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isError
                    ? colorScheme.onErrorContainer
                    : colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Visual tone for [_SettingsStatusBanner].
enum _StatusBannerTone { success, error }

/// Informational card describing WebDAV single-file Markdown synchronization.
class _WebDavInfoCard extends StatelessWidget {
  /// Creates a [_WebDavInfoCard].
  const _WebDavInfoCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final localizations = AppLocalizations.of(context);

    return Card(
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_sync_outlined, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    localizations.webdavSectionTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              localizations.webdavSectionDescription,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
