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

/// Immutable configuration for WebDAV synchronization and application language.
@immutable
class WebDavConfig {
  /// Creates a [WebDavConfig] instance.
  const WebDavConfig({
    this.serverUrl = '',
    this.username = '',
    this.password = '',
    this.filePath = 'tiertask.md',
    this.language = AppLanguage.system,
  });

  static final RegExp _leadingSlashesPattern = RegExp(r'^/+');

  /// WebDAV server base URL or full endpoint URL.
  final String serverUrl;

  /// WebDAV username.
  final String username;

  /// WebDAV password or application password.
  final String password;

  /// Remote Markdown file name or relative path (for example `tiertask.md`).
  final String filePath;

  /// Selected display language preference (`system`, `english`, or `german`).
  final AppLanguage language;

  /// Whether all required WebDAV connection fields are populated.
  bool get isConfigured =>
      serverUrl.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      password.isNotEmpty;

  /// Returns a copy of this configuration with updated fields.
  WebDavConfig copyWith({
    String? serverUrl,
    String? username,
    String? password,
    String? filePath,
    AppLanguage? language,
  }) {
    return WebDavConfig(
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      filePath: filePath ?? this.filePath,
      language: language ?? this.language,
    );
  }

  /// Resolves the full WebDAV endpoint [Uri] for the target Markdown file.
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

    final cleanFile = filePath.trim().isEmpty
        ? 'tiertask.md'
        : filePath.trim().replaceFirst(_leadingSlashesPattern, '');

    final encodedFileSegments = cleanFile
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');

    final String fullUrl;
    if (rawUrl.toLowerCase().endsWith('.md')) {
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
        other.language == language;
  }

  @override
  int get hashCode =>
      Object.hash(serverUrl, username, password, filePath, language);
}
