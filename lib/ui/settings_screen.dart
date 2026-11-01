import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/webdav_config.dart';
import '../providers/task_providers.dart';

/// Settings screen for Nextcloud WebDAV connection parameters and manual sync test.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _serverUrlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _filePathController;

  bool _obscurePassword = true;
  bool _initialized = false;
  bool _isTesting = false;
  String? _statusBannerMessage;
  bool _statusIsError = false;

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

  void _populateFieldsIfNeeded(WebDavConfig config) {
    if (_initialized) return;
    _initialized = true;
    _serverUrlController.text = config.serverUrl;
    _usernameController.text = config.username;
    _passwordController.text = config.password;
    _filePathController.text =
        config.filePath.isEmpty ? 'tiertask.md' : config.filePath;
  }

  WebDavConfig _buildCurrentConfig() {
    return WebDavConfig(
      serverUrl: _serverUrlController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      filePath: _filePathController.text.trim().isEmpty
          ? 'tiertask.md'
          : _filePathController.text.trim(),
    );
  }

  Future<void> _saveOnly() async {
    if (!_formKey.currentState!.validate()) return;
    final config = _buildCurrentConfig();
    await ref.read(webDavConfigProvider.notifier).updateConfig(config);
    if (!mounted) return;
    setState(() {
      _statusIsError = false;
      _statusBannerMessage = 'Zugangsdaten lokal gespeichert.';
    });
  }

  Future<void> _testConnectionAndSync() async {
    if (!_formKey.currentState!.validate()) return;
    final config = _buildCurrentConfig();

    setState(() {
      _isTesting = true;
      _statusBannerMessage = null;
      _statusIsError = false;
    });

    try {
      await ref.read(taskNotifierProvider.notifier).testConnectionAndSync(config);
      if (!mounted) return;
      setState(() {
        _isTesting = false;
        _statusIsError = false;
        _statusBannerMessage =
            'Verbindung erfolgreich! Markdown-Datei wurde mit Nextcloud synchronisiert.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isTesting = false;
        _statusIsError = true;
        _statusBannerMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(webDavConfigProvider);
    if (configAsync.hasValue) {
      _populateFieldsIfNeeded(configAsync.value!);
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final previewConfig = _buildCurrentConfig();
    final resolvedUri = previewConfig.resolveEndpointUri();

    return Scaffold(
      appBar: AppBar(
        title: const Text('WebDAV Einstellungen'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          onChanged: () => setState(() {}),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: colorScheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.cloud_sync_outlined,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Nextcloud WebDAV (Single Source of Truth)',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'TierTask speichert alle Aufgaben in einer einzigen Markdown-Datei '
                        '(tiertask.md oder t2.md) auf deinem Nextcloud-Server. '
                        'Empfehlung: Erstelle in Nextcloud unter Sicherheit ein eigenes App-Passwort.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _serverUrlController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Nextcloud Server-URL oder WebDAV-URL',
                  hintText: 'https://cloud.example.com',
                  prefixIcon: Icon(Icons.dns_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Bitte Server-URL eingeben.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Benutzername',
                  hintText: 'stefan',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Bitte Benutzername eingeben.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'App-Passwort / Passwort',
                  prefixIcon: const Icon(Icons.key_outlined),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? 'Passwort anzeigen'
                        : 'Passwort verbergen',
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Bitte Passwort oder App-Passwort eingeben.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _filePathController,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Markdown-Dateiname / Pfad',
                  hintText: 'tiertask.md oder t2.md',
                  prefixIcon: Icon(Icons.description_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    label: const Text('tiertask.md'),
                    onPressed: () {
                      setState(() {
                        _filePathController.text = 'tiertask.md';
                      });
                    },
                  ),
                  ActionChip(
                    label: const Text('t2.md'),
                    onPressed: () {
                      setState(() {
                        _filePathController.text = 't2.md';
                      });
                    },
                  ),
                ],
              ),
              if (resolvedUri != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Aufgelöster WebDAV-Endpunkt (GET / PUT):',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        resolvedUri.toString(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              if (_statusBannerMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _statusIsError
                        ? colorScheme.errorContainer
                        : colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _statusIsError
                            ? Icons.error_outline_rounded
                            : Icons.check_circle_outline_rounded,
                        color: _statusIsError
                            ? colorScheme.onErrorContainer
                            : colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _statusBannerMessage!,
                          style: TextStyle(
                            color: _statusIsError
                                ? colorScheme.onErrorContainer
                                : colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isTesting ? null : _saveOnly,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Speichern'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _isTesting ? null : _testConnectionAndSync,
                      icon: _isTesting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_rounded),
                      label: const Text('Test Connection / Sync Now'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
