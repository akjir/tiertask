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

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/webdav_config.dart';

/// Repository contract for persisting storage mode, file paths, WebDAV credentials,
/// language, and theme settings.
abstract class SettingsRepository {
  /// Loads the persisted [WebDavConfig].
  Future<WebDavConfig> loadConfig();

  /// Saves [config] to persistent storage.
  Future<void> saveConfig(WebDavConfig config);
}

/// Encrypted settings repository backed by [FlutterSecureStorage].
class SecureSettingsRepository implements SettingsRepository {
  /// Creates a [SecureSettingsRepository] with an optional [storage] instance.
  SecureSettingsRepository({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _keyFilePath = 't2_webdav_file_path';
  static const String _keyLanguage = 't2_app_language';
  static const String _keyLocalFilePath = 't2_local_file_path';
  static const String _keyPassword = 't2_webdav_password';
  static const String _keyServerUrl = 't2_webdav_server_url';
  static const String _keyShowOpenTaskCount = 't2_show_open_task_count';
  static const String _keyStorageMode = 't2_storage_mode';
  static const String _keyThemeMode = 't2_theme_mode';
  static const String _keyUsername = 't2_webdav_username';

  final FlutterSecureStorage _storage;

  @override
  Future<WebDavConfig> loadConfig() async {
    try {
      final serverUrl = await _storage.read(key: _keyServerUrl) ?? '';
      final username = await _storage.read(key: _keyUsername) ?? '';
      final password = await _storage.read(key: _keyPassword) ?? '';
      final filePath = await _storage.read(key: _keyFilePath) ?? 'tiertask.md';
      final localFilePath =
          await _storage.read(key: _keyLocalFilePath) ?? 'tiertask.md';
      final rawStorageMode = await _storage.read(key: _keyStorageMode);
      final rawLanguage = await _storage.read(key: _keyLanguage);
      final rawThemeMode = await _storage.read(key: _keyThemeMode);
      final rawShowOpenTaskCount = await _storage.read(
        key: _keyShowOpenTaskCount,
      );

      return WebDavConfig(
        serverUrl: serverUrl,
        username: username,
        password: password,
        filePath: filePath.trim().isEmpty ? 'tiertask.md' : filePath,
        localFilePath: localFilePath.trim().isEmpty
            ? 'tiertask.md'
            : localFilePath,
        storageMode: rawStorageMode == null
            ? null
            : StorageMode.fromCode(rawStorageMode),
        language: AppLanguage.fromCode(rawLanguage),
        themeMode: AppThemeMode.fromCode(rawThemeMode),
        showOpenTaskCount: rawShowOpenTaskCount?.trim().toLowerCase() == 'true',
      );
    } on Object {
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
    await _storage.write(
      key: _keyLocalFilePath,
      value: config.localFilePath.trim().isEmpty
          ? 'tiertask.md'
          : config.localFilePath.trim(),
    );
    await _storage.write(key: _keyStorageMode, value: config.storageMode.code);
    await _storage.write(key: _keyLanguage, value: config.language.code);
    await _storage.write(key: _keyThemeMode, value: config.themeMode.code);
    await _storage.write(
      key: _keyShowOpenTaskCount,
      value: config.showOpenTaskCount.toString(),
    );
  }
}

/// In-memory [SettingsRepository] implementation for unit and widget tests.
class InMemorySettingsRepository implements SettingsRepository {
  /// Creates an [InMemorySettingsRepository] initialized with [_config].
  InMemorySettingsRepository([this._config = const WebDavConfig()]);

  WebDavConfig _config;

  @override
  Future<WebDavConfig> loadConfig() async => _config;

  @override
  Future<void> saveConfig(WebDavConfig config) async {
    _config = config;
  }
}
