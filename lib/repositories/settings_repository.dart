import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/webdav_config.dart';

/// Repository for persisting Nextcloud WebDAV credentials securely on the device.
abstract class SettingsRepository {
  Future<WebDavConfig> loadConfig();
  Future<void> saveConfig(WebDavConfig config);
}

class SecureSettingsRepository implements SettingsRepository {
  SecureSettingsRepository({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _keyServerUrl = 't2_webdav_server_url';
  static const String _keyUsername = 't2_webdav_username';
  static const String _keyPassword = 't2_webdav_password';
  static const String _keyFilePath = 't2_webdav_file_path';

  @override
  Future<WebDavConfig> loadConfig() async {
    try {
      final serverUrl = await _storage.read(key: _keyServerUrl) ?? '';
      final username = await _storage.read(key: _keyUsername) ?? '';
      final password = await _storage.read(key: _keyPassword) ?? '';
      final filePath = await _storage.read(key: _keyFilePath) ?? 'tiertask.md';
      return WebDavConfig(
        serverUrl: serverUrl,
        username: username,
        password: password,
        filePath: filePath.trim().isEmpty ? 'tiertask.md' : filePath,
      );
    } catch (_) {
      return const WebDavConfig();
    }
  }

  @override
  Future<void> saveConfig(WebDavConfig config) async {
    await _storage.write(key: _keyServerUrl, value: config.serverUrl.trim());
    await _storage.write(key: _keyUsername, value: config.username.trim());
    await _storage.write(key: _keyPassword, value: config.password);
    await _storage.write(
      key: _keyFilePath,
      value: config.filePath.trim().isEmpty
          ? 'tiertask.md'
          : config.filePath.trim(),
    );
  }
}

/// In-memory implementation for unit and widget tests.
class InMemorySettingsRepository implements SettingsRepository {
  InMemorySettingsRepository([this._config = const WebDavConfig()]);

  WebDavConfig _config;

  @override
  Future<WebDavConfig> loadConfig() async => _config;

  @override
  Future<void> saveConfig(WebDavConfig config) async {
    _config = config;
  }
}
