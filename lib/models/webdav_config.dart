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

/// Supported display language modes in TierTask.
enum AppLanguage {
  /// Follows the operating system language (`de` -> German, otherwise English default).
  system(code: 'system'),

  /// Forces English (`en`).
  english(code: 'en'),

  /// Forces German (`de`).
  german(code: 'de');

  /// Creates an [AppLanguage] option.
  const AppLanguage({required this.code});

  /// Storage identifier persisted in settings (`'system'`, `'en'`, or `'de'`).
  final String code;

  /// Resolves an [AppLanguage] from its persisted [rawCode], defaulting to [AppLanguage.system].
  static AppLanguage fromCode(String? rawCode) {
    return switch (rawCode?.trim().toLowerCase()) {
      'en' => AppLanguage.english,
      'de' => AppLanguage.german,
      _ => AppLanguage.system,
    };
  }

  /// Resolves the effective [Locale] (`en` or `de`) given the host [platformLocale].
  ///
  /// English (`en`) is the default fallback whenever [AppLanguage.system] is active
  /// on a non-German operating system.
  Locale resolveLocale(Locale? platformLocale) {
    return switch (this) {
      AppLanguage.english => const Locale('en'),
      AppLanguage.german => const Locale('de'),
      AppLanguage.system =>
        platformLocale?.languageCode.toLowerCase() == 'de'
            ? const Locale('de')
            : const Locale('en'),
    };
  }
}

/// Supported color theme modes in TierTask.
enum AppThemeMode {
  /// Follows the operating system brightness setting.
  system(code: 'system'),

  /// Forces the light Material 3 theme.
  light(code: 'light'),

  /// Forces the dark Material 3 theme.
  dark(code: 'dark');

  /// Creates an [AppThemeMode] option.
  const AppThemeMode({required this.code});

  /// Storage identifier persisted in settings (`'system'`, `'light'`, or `'dark'`).
  final String code;

  /// Resolves an [AppThemeMode] from its persisted [rawCode], defaulting to [AppThemeMode.system].
  static AppThemeMode fromCode(String? rawCode) {
    return switch (rawCode?.trim().toLowerCase()) {
      'light' => AppThemeMode.light,
      'dark' => AppThemeMode.dark,
      _ => AppThemeMode.system,
    };
  }
}

/// Supported TDF persistence and synchronization modes in TierTask.
enum StorageMode {
  /// Persists the `.tdf` file only on the local filesystem.
  local(code: 'local'),

  /// Synchronizes the `.tdf` file only with a remote WebDAV server.
  webdav(code: 'webdav'),

  /// Persists the `.tdf` file locally and synchronizes it with a WebDAV server.
  both(code: 'both');

  /// Creates a [StorageMode] option.
  const StorageMode({required this.code});

  /// Storage identifier persisted in settings (`'local'`, `'webdav'`, or `'both'`).
  final String code;

  /// Whether local `.tdf` file persistence is enabled in this mode.
  bool get usesLocal => this == StorageMode.local || this == StorageMode.both;

  /// Whether remote WebDAV synchronization is enabled in this mode.
  bool get usesWebDav => this == StorageMode.webdav || this == StorageMode.both;

  /// Resolves a [StorageMode] from its persisted [rawCode], defaulting to [StorageMode.local].
  static StorageMode fromCode(String? rawCode) {
    return switch (rawCode?.trim().toLowerCase()) {
      'webdav' => StorageMode.webdav,
      'both' => StorageMode.both,
      _ => StorageMode.local,
    };
  }
}

/// Immutable configuration for local TDF file storage, WebDAV synchronization, language, theme, and task count visibility.
@immutable
class WebDavConfig {
  /// Creates a [WebDavConfig] instance.
  const WebDavConfig({
    this.serverUrl = '',
    this.username = '',
    this.password = '',
    this.filePath = 'tiertask.tdf',
    this.localFilePath = 'tiertask.tdf',
    StorageMode? storageMode,
    this.language = AppLanguage.system,
    this.themeMode = AppThemeMode.system,
    this.showOpenTaskCount = false,
  }) : storageMode =
           storageMode ??
           (serverUrl != '' && username != '' && password != ''
               ? StorageMode.webdav
               : StorageMode.local);

  static final RegExp _leadingSlashesPattern = RegExp(r'^/+');

  /// WebDAV server base URL or full endpoint URL.
  final String serverUrl;

  /// WebDAV username.
  final String username;

  /// WebDAV password or application password.
  final String password;

  /// Remote `.tdf` file name or relative path on the WebDAV server.
  final String filePath;

  /// Local `.tdf` file name or path on the device filesystem.
  final String localFilePath;

  /// Active persistence mode (`local`, `webdav`, or `both`).
  final StorageMode storageMode;

  /// Selected display language preference (`system`, `english`, or `german`).
  final AppLanguage language;

  /// Selected color theme preference (`system`, `light`, or `dark`).
  final AppThemeMode themeMode;

  /// Whether to display the total open task count on category and location cards.
  final bool showOpenTaskCount;

  /// Whether at least one storage backend required by [storageMode] is ready for I/O.
  bool get hasActiveStorage {
    return switch (storageMode) {
      StorageMode.local => isLocalConfigured,
      StorageMode.webdav => isWebDavConfigured,
      StorageMode.both => isLocalConfigured || isWebDavConfigured,
    };
  }

  /// Whether all storage backends required by [storageMode] are fully configured.
  bool get isConfigured {
    return switch (storageMode) {
      StorageMode.local => isLocalConfigured,
      StorageMode.webdav => isWebDavConfigured,
      StorageMode.both => isLocalConfigured && isWebDavConfigured,
    };
  }

  /// Whether the local `.tdf` file name or path is non-empty.
  bool get isLocalConfigured => localFilePath.trim().isNotEmpty;

  /// Whether all required WebDAV connection fields are populated.
  bool get isWebDavConfigured =>
      serverUrl.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      password.isNotEmpty &&
      resolveEndpointUri() != null;

  /// Returns a copy of this configuration with updated fields.
  WebDavConfig copyWith({
    String? serverUrl,
    String? username,
    String? password,
    String? filePath,
    String? localFilePath,
    StorageMode? storageMode,
    AppLanguage? language,
    AppThemeMode? themeMode,
    bool? showOpenTaskCount,
  }) {
    return WebDavConfig(
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      filePath: filePath ?? this.filePath,
      localFilePath: localFilePath ?? this.localFilePath,
      storageMode: storageMode ?? this.storageMode,
      language: language ?? this.language,
      themeMode: themeMode ?? this.themeMode,
      showOpenTaskCount: showOpenTaskCount ?? this.showOpenTaskCount,
    );
  }

  /// Resolves the full WebDAV endpoint [Uri] for the target `.tdf` file.
  Uri? resolveEndpointUri() {
    var rawUrl = serverUrl.trim();
    if (rawUrl.isEmpty) {
      return null;
    }

    if (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://')) {
      rawUrl = 'https://$rawUrl';
    }

    while (rawUrl.endsWith('/')) {
      rawUrl = rawUrl.substring(0, rawUrl.length - 1);
    }

    final baseUri = Uri.tryParse(rawUrl);
    if (baseUri == null || !baseUri.hasScheme || baseUri.host.isEmpty) {
      return null;
    }

    final cleanFile = filePath.trim().isEmpty
        ? 'tiertask.tdf'
        : filePath.trim().replaceFirst(_leadingSlashesPattern, '');

    final encodedFileSegments = cleanFile
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');

    final String fullUrl;
    if (rawUrl.toLowerCase().endsWith('.tdf')) {
      fullUrl = rawUrl;
    } else if (rawUrl.contains('/remote.php/dav/files/') ||
        rawUrl.contains('/remote.php/webdav')) {
      fullUrl = '$rawUrl/$encodedFileSegments';
    } else {
      final cleanUser = username.trim();
      if (cleanUser.isEmpty) {
        fullUrl = '$rawUrl/remote.php/webdav/$encodedFileSegments';
      } else {
        fullUrl =
            '$rawUrl/remote.php/dav/files/${Uri.encodeComponent(cleanUser)}/$encodedFileSegments';
      }
    }

    return Uri.tryParse(fullUrl);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WebDavConfig &&
        other.serverUrl == serverUrl &&
        other.username == username &&
        other.password == password &&
        other.filePath == filePath &&
        other.localFilePath == localFilePath &&
        other.storageMode == storageMode &&
        other.language == language &&
        other.themeMode == themeMode &&
        other.showOpenTaskCount == showOpenTaskCount;
  }

  @override
  int get hashCode => Object.hash(
    serverUrl,
    username,
    password,
    filePath,
    localFilePath,
    storageMode,
    language,
    themeMode,
    showOpenTaskCount,
  );
}
