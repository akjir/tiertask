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
  system(id: 0),

  /// Forces English (`en`).
  english(id: 1),

  /// Forces German (`de`).
  german(id: 2);

  /// Creates an [AppLanguage] option.
  const AppLanguage({required this.id});

  /// Compact 2-bit binary identifier (`0`, `1`, or `2`).
  final int id;

  /// Resolves an [AppLanguage] from its binary [rawId], defaulting to [AppLanguage.system].
  static AppLanguage fromId(int rawId) {
    return switch (rawId) {
      1 => AppLanguage.english,
      2 => AppLanguage.german,
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
  system(id: 0),

  /// Forces the light Material 3 theme.
  light(id: 1),

  /// Forces the dark Material 3 theme.
  dark(id: 2);

  /// Creates an [AppThemeMode] option.
  const AppThemeMode({required this.id});

  /// Compact 2-bit binary identifier (`0`, `1`, or `2`).
  final int id;

  /// Resolves an [AppThemeMode] from its binary [rawId], defaulting to [AppThemeMode.system].
  static AppThemeMode fromId(int rawId) {
    return switch (rawId) {
      1 => AppThemeMode.light,
      2 => AppThemeMode.dark,
      _ => AppThemeMode.system,
    };
  }
}

/// Supported Material 3 color theme palettes in TierTask.
enum AppThemePalette {
  /// Chromium-inspired Material 3 slate blue-grey palette (default).
  slate(id: 0),

  /// Signature TierTask navy and indigo palette.
  navy(id: 1);

  /// Creates an [AppThemePalette] option.
  const AppThemePalette({required this.id});

  /// Compact 1-bit binary identifier (`0` or `1`).
  final int id;

  /// Resolves an [AppThemePalette] from its binary [rawId], defaulting to [AppThemePalette.slate].
  static AppThemePalette fromId(int rawId) {
    return switch (rawId) {
      1 => AppThemePalette.navy,
      _ => AppThemePalette.slate,
    };
  }
}

/// Supported time zone resolution modes in TierTask.
enum AppTimeZoneMode {
  /// Uses the operating system's local time zone automatically.
  automatic(id: 0),

  /// Uses a manually configured fixed UTC offset (`manualTimeZoneOffsetMinutes`).
  manual(id: 1);

  /// Creates an [AppTimeZoneMode] option.
  const AppTimeZoneMode({required this.id});

  /// Compact 1-bit binary identifier (`0` or `1`).
  final int id;

  /// Resolves an [AppTimeZoneMode] from its binary [rawId], defaulting to [AppTimeZoneMode.automatic].
  static AppTimeZoneMode fromId(int rawId) {
    return switch (rawId) {
      1 => AppTimeZoneMode.manual,
      _ => AppTimeZoneMode.automatic,
    };
  }
}

/// Supported TDF persistence and synchronization modes in TierTask.
enum StorageMode {
  /// Persists the `.tdf` file only on the local filesystem.
  local(id: 0),

  /// Synchronizes the `.tdf` file only with a remote WebDAV server.
  webdav(id: 1),

  /// Persists the `.tdf` file locally and synchronizes it with a WebDAV server.
  both(id: 2);

  /// Creates a [StorageMode] option.
  const StorageMode({required this.id});

  /// Compact 2-bit binary identifier (`0`, `1`, or `2`).
  final int id;

  /// Whether local `.tdf` file persistence is enabled in this mode.
  bool get usesLocal => this == StorageMode.local || this == StorageMode.both;

  /// Whether remote WebDAV synchronization is enabled in this mode.
  bool get usesWebDav => this == StorageMode.webdav || this == StorageMode.both;

  /// Resolves a [StorageMode] from its binary [rawId], defaulting to [StorageMode.local].
  static StorageMode fromId(int rawId) {
    return switch (rawId) {
      1 => StorageMode.webdav,
      2 => StorageMode.both,
      _ => StorageMode.local,
    };
  }
}

/// Immutable configuration for local TDF file storage, WebDAV synchronization, language, theme, and time zone.
@immutable
class WebDavConfig {
  /// Creates a [WebDavConfig] instance.
  const WebDavConfig({
    this.serverUrl = '',
    this.username = '',
    this.password = '',
    this.filePath = defaultFileName,
    this.localFilePath = defaultFileName,
    StorageMode? storageMode,
    this.language = AppLanguage.system,
    this.themeMode = AppThemeMode.system,
    this.themePalette = AppThemePalette.slate,
    this.locationEnabled = false,
    this.timeZoneMode = AppTimeZoneMode.automatic,
    int manualTimeZoneOffsetMinutes = 0,
  }) : storageMode =
           storageMode ??
           (serverUrl != '' && username != '' && password != ''
               ? StorageMode.webdav
               : StorageMode.local),
       manualTimeZoneOffsetMinutes =
           manualTimeZoneOffsetMinutes < minUtcOffsetMinutes
           ? minUtcOffsetMinutes
           : (manualTimeZoneOffsetMinutes > maxUtcOffsetMinutes
                 ? maxUtcOffsetMinutes
                 : manualTimeZoneOffsetMinutes);

  /// Default `.tdf` file name used by the default `Tasks` workspace.
  static const String defaultFileName = 'tasks.tdf';

  /// Maximum supported UTC offset in minutes (`+14:00`).
  static const int maxUtcOffsetMinutes = 840;

  /// Minimum supported UTC offset in minutes (`-12:00`).
  static const int minUtcOffsetMinutes = -720;

  /// Standard selectable UTC offsets in minutes (`UTC-12:00` through `UTC+14:00`).
  static const List<int> supportedUtcOffsetMinutes = <int>[
    -720,
    -660,
    -600,
    -570,
    -540,
    -480,
    -420,
    -360,
    -300,
    -240,
    -210,
    -180,
    -120,
    -60,
    0,
    60,
    120,
    180,
    210,
    240,
    270,
    300,
    330,
    345,
    360,
    390,
    420,
    480,
    540,
    570,
    600,
    630,
    660,
    720,
    765,
    780,
    840,
  ];

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

  /// Selected Material 3 color palette (`slate` or `navy`).
  final AppThemePalette themePalette;

  /// Whether foreground location determination is enabled while the application is running.
  final bool locationEnabled;

  /// Selected time zone resolution mode (`automatic` or `manual`).
  final AppTimeZoneMode timeZoneMode;

  /// Manually configured UTC offset in minutes (`-720..840`) when [timeZoneMode] is [AppTimeZoneMode.manual].
  final int manualTimeZoneOffsetMinutes;

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
    AppThemePalette? themePalette,
    bool? locationEnabled,
    AppTimeZoneMode? timeZoneMode,
    int? manualTimeZoneOffsetMinutes,
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
      themePalette: themePalette ?? this.themePalette,
      locationEnabled: locationEnabled ?? this.locationEnabled,
      timeZoneMode: timeZoneMode ?? this.timeZoneMode,
      manualTimeZoneOffsetMinutes:
          manualTimeZoneOffsetMinutes ?? this.manualTimeZoneOffsetMinutes,
    );
  }

  /// Formats [offsetMinutes] as an ISO-style `UTC±HH:MM` label.
  static String formatUtcOffset(int offsetMinutes) {
    final clamped = offsetMinutes < minUtcOffsetMinutes
        ? minUtcOffsetMinutes
        : (offsetMinutes > maxUtcOffsetMinutes
              ? maxUtcOffsetMinutes
              : offsetMinutes);
    final sign = clamped < 0 ? '-' : '+';
    final absolute = clamped.abs();
    final hours = (absolute ~/ 60).toString().padLeft(2, '0');
    final minutes = (absolute % 60).toString().padLeft(2, '0');
    return 'UTC$sign$hours:$minutes';
  }

  /// Converts a wall-clock [localWallClock] date-time into a second-precision UTC [DateTime]
  /// according to [timeZoneMode] and [manualTimeZoneOffsetMinutes].
  DateTime localWallClockToUtc(DateTime localWallClock) {
    if (timeZoneMode == AppTimeZoneMode.manual) {
      final wallAsUtc = DateTime.utc(
        localWallClock.year,
        localWallClock.month,
        localWallClock.day,
        localWallClock.hour,
        localWallClock.minute,
        localWallClock.second,
      );
      return wallAsUtc.subtract(Duration(minutes: manualTimeZoneOffsetMinutes));
    }
    final osLocal = DateTime(
      localWallClock.year,
      localWallClock.month,
      localWallClock.day,
      localWallClock.hour,
      localWallClock.minute,
      localWallClock.second,
    ).toUtc();
    return DateTime.utc(
      osLocal.year,
      osLocal.month,
      osLocal.day,
      osLocal.hour,
      osLocal.minute,
      osLocal.second,
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
        ? defaultFileName
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

  /// Converts [instant] into a wall-clock [DateTime] (encoded with `isUtc: true` components
  /// for deterministic field access) according to [timeZoneMode] and [manualTimeZoneOffsetMinutes].
  DateTime toLocalWallClock(DateTime instant) {
    final utc = instant.toUtc();
    if (timeZoneMode == AppTimeZoneMode.manual) {
      final shifted = utc.add(Duration(minutes: manualTimeZoneOffsetMinutes));
      return DateTime.utc(
        shifted.year,
        shifted.month,
        shifted.day,
        shifted.hour,
        shifted.minute,
        shifted.second,
      );
    }
    final local = utc.toLocal();
    return DateTime.utc(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
      local.second,
    );
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
        other.themePalette == themePalette &&
        other.locationEnabled == locationEnabled &&
        other.timeZoneMode == timeZoneMode &&
        other.manualTimeZoneOffsetMinutes == manualTimeZoneOffsetMinutes;
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
    themePalette,
    locationEnabled,
    timeZoneMode,
    manualTimeZoneOffsetMinutes,
  );
}
