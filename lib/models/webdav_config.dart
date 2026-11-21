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

import '../services/app_logger.dart';
import 'tdf_timezone.dart';

/// Supported display language modes in TierTask.
enum AppLanguage {
  /// Follows the operating system language (`de` -> German, otherwise English default).
  system(jsonValue: 'system'),

  /// Forces English (`en`).
  english(jsonValue: 'english'),

  /// Forces German (`de`).
  german(jsonValue: 'german');

  /// Creates an [AppLanguage] option.
  const AppLanguage({required this.jsonValue});

  /// Canonical lowercase JSON token persisted in `settings.json`.
  final String jsonValue;

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

  /// Parses a canonical JSON token into an [AppLanguage], or returns `null` when unknown.
  static AppLanguage? tryParseJson(String? raw) {
    if (raw == null) {
      return null;
    }
    return switch (raw.trim().toLowerCase()) {
      'system' => AppLanguage.system,
      'english' => AppLanguage.english,
      'german' => AppLanguage.german,
      _ => null,
    };
  }
}

/// Supported color theme modes in TierTask.
enum AppThemeMode {
  /// Follows the operating system brightness setting.
  system(jsonValue: 'system'),

  /// Forces the light Material 3 theme.
  light(jsonValue: 'light'),

  /// Forces the dark Material 3 theme.
  dark(jsonValue: 'dark');

  /// Creates an [AppThemeMode] option.
  const AppThemeMode({required this.jsonValue});

  /// Canonical lowercase JSON token persisted in `settings.json`.
  final String jsonValue;

  /// Parses a canonical JSON token into an [AppThemeMode], or returns `null` when unknown.
  static AppThemeMode? tryParseJson(String? raw) {
    if (raw == null) {
      return null;
    }
    return switch (raw.trim().toLowerCase()) {
      'system' => AppThemeMode.system,
      'light' => AppThemeMode.light,
      'dark' => AppThemeMode.dark,
      _ => null,
    };
  }
}

/// Supported color theme palettes in TierTask (`spec/UI_DESIGN_SYSTEM.md` `U-TOKEN-005`).
enum AppThemePalette {
  /// Default WCAG AA verified Calm slate-teal palette (`calm`).
  calm(jsonValue: 'calm'),

  /// Warm WCAG AA verified Plum Umber palette (`plum_umber`).
  plumUmber(jsonValue: 'plum_umber');

  /// Creates an [AppThemePalette] option.
  const AppThemePalette({required this.jsonValue});

  /// Canonical lowercase JSON token persisted in `settings.json`.
  final String jsonValue;

  /// Parses a canonical JSON token into an [AppThemePalette], silently migrating
  /// legacy `'slate'` and `'navy'` values to [AppThemePalette.calm], or returns
  /// `null` when unknown.
  static AppThemePalette? tryParseJson(String? raw) {
    if (raw == null) {
      return null;
    }
    return switch (raw.trim().toLowerCase()) {
      'calm' => AppThemePalette.calm,
      'plum_umber' => AppThemePalette.plumUmber,
      'slate' || 'navy' => AppThemePalette.calm,
      _ => null,
    };
  }
}

/// Supported time zone resolution modes in TierTask.
enum AppTimeZoneMode {
  /// Uses the operating system's local time zone automatically.
  automatic(jsonValue: 'automatic'),

  /// Uses a manually configured fixed UTC offset (`manualTimeZoneOffsetMinutes`).
  manual(jsonValue: 'manual');

  /// Creates an [AppTimeZoneMode] option.
  const AppTimeZoneMode({required this.jsonValue});

  /// Canonical lowercase JSON token persisted in `settings.json`.
  final String jsonValue;

  /// Parses a canonical JSON token into an [AppTimeZoneMode], or returns `null` when unknown.
  static AppTimeZoneMode? tryParseJson(String? raw) {
    if (raw == null) {
      return null;
    }
    return switch (raw.trim().toLowerCase()) {
      'automatic' => AppTimeZoneMode.automatic,
      'manual' => AppTimeZoneMode.manual,
      _ => null,
    };
  }
}

/// Per-workspace lead horizon before `due` during which non-`passive` open
/// queued tasks gain derived effective priority (`spec/TDF_SPEC_0.8.0.md` Section 9.5).
enum DueLeadWindow {
  /// Disables deadline-driven effective priority (`W_due = null`).
  off(jsonValue: 'off', duration: null),

  /// Enables effective priority at exact deadline arrival (`W_due = 0s`).
  atDue(jsonValue: 'at_due', duration: Duration.zero),

  /// Enables effective priority `12 hours` (`43,200s`) before `due`.
  hours12(jsonValue: 'hours12', duration: Duration(hours: 12)),

  /// Normative default lead window of `24 hours` (`86,400s`) before `due`.
  hours24(jsonValue: 'hours24', duration: Duration(hours: 24)),

  /// Enables effective priority `48 hours` (`172,800s`) before `due`.
  hours48(jsonValue: 'hours48', duration: Duration(hours: 48)),

  /// Enables effective priority `7 days` (`604,800s`) before `due`.
  days7(jsonValue: 'days7', duration: Duration(days: 7));

  /// Creates a [DueLeadWindow] option.
  const DueLeadWindow({required this.jsonValue, required this.duration});

  /// Lead-window duration passed to `TaskBoard`, or `null` when [off].
  final Duration? duration;

  /// Canonical lowercase JSON token persisted in `settings.json`.
  final String jsonValue;

  /// Parses a canonical JSON token into a [DueLeadWindow], or returns `null` when unknown.
  static DueLeadWindow? tryParseJson(String? raw) {
    if (raw == null) {
      return null;
    }
    return switch (raw.trim().toLowerCase()) {
      'off' => DueLeadWindow.off,
      'at_due' => DueLeadWindow.atDue,
      'hours12' => DueLeadWindow.hours12,
      'hours24' => DueLeadWindow.hours24,
      'hours48' => DueLeadWindow.hours48,
      'days7' => DueLeadWindow.days7,
      _ => null,
    };
  }
}

/// Supported TDF persistence and synchronization modes in TierTask.
enum StorageMode {
  /// Persists the `.tdf` file only on the local filesystem.
  local(jsonValue: 'local'),

  /// Synchronizes the `.tdf` file only with a remote WebDAV server.
  webdav(jsonValue: 'webdav'),

  /// Persists the `.tdf` file locally and synchronizes it with a WebDAV server.
  both(jsonValue: 'both');

  /// Creates a [StorageMode] option.
  const StorageMode({required this.jsonValue});

  /// Canonical lowercase JSON token persisted in `settings.json`.
  final String jsonValue;

  /// Whether local `.tdf` file persistence is enabled in this mode.
  bool get usesLocal => this == StorageMode.local || this == StorageMode.both;

  /// Whether remote WebDAV synchronization is enabled in this mode.
  bool get usesWebDav => this == StorageMode.webdav || this == StorageMode.both;

  /// Parses a canonical JSON token into a [StorageMode], or returns `null` when unknown.
  static StorageMode? tryParseJson(String? raw) {
    if (raw == null) {
      return null;
    }
    return switch (raw.trim().toLowerCase()) {
      'local' => StorageMode.local,
      'webdav' => StorageMode.webdav,
      'both' => StorageMode.both,
      _ => null,
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
    this.themePalette = AppThemePalette.calm,
    this.locationEnabled = false,
    this.timeZoneMode = AppTimeZoneMode.automatic,
    int manualTimeZoneOffsetMinutes = 0,
    this.diagnosticsEnabled = false,
    this.logLevel = LogLevel.info,
    this.logStorageMode = StorageMode.local,
    this.localWatchEnabled = true,
    this.dueLeadWindow = DueLeadWindow.hours24,
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

  /// Whether opt-in diagnostic logging (`tiertask_<date>_<platform>_<workspace>.log`) is enabled.
  final bool diagnosticsEnabled;

  /// Minimum severity threshold for recorded diagnostic log entries.
  final LogLevel logLevel;

  /// Persistence target for diagnostic logs (`local`, `webdav`, or `both`).
  final StorageMode logStorageMode;

  /// Whether automatic parent-directory observation for external local `.tdf` edits is enabled.
  final bool localWatchEnabled;

  /// Per-workspace lead horizon before `due` for automatic effective priority promotion.
  final DueLeadWindow dueLeadWindow;

  /// Whether opt-in diagnostic logging is enabled (alias for [diagnosticsEnabled]).
  bool get enableLogging => diagnosticsEnabled;

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
    bool? diagnosticsEnabled,
    LogLevel? logLevel,
    StorageMode? logStorageMode,
    bool? localWatchEnabled,
    DueLeadWindow? dueLeadWindow,
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
      diagnosticsEnabled: diagnosticsEnabled ?? this.diagnosticsEnabled,
      logLevel: logLevel ?? this.logLevel,
      logStorageMode: logStorageMode ?? this.logStorageMode,
      localWatchEnabled: localWatchEnabled ?? this.localWatchEnabled,
      dueLeadWindow: dueLeadWindow ?? this.dueLeadWindow,
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
  /// according to [timeZoneMode] and [manualTimeZoneOffsetMinutes] via `TDF-CAL-001`.
  DateTime localWallClockToUtc(DateTime localWallClock) {
    return resolveTimeZoneContext().resolveLocalToUtc(
      localWallClock.year,
      localWallClock.month,
      localWallClock.day,
      localWallClock.hour,
      localWallClock.minute,
      localWallClock.second,
    );
  }

  /// Resolves the full WebDAV endpoint [Uri] for the target `.tdf` file.
  Uri? resolveEndpointUri() {
    var rawUrl = serverUrl.trim();
    if (rawUrl.isEmpty || _hasControlCharacters(rawUrl)) {
      return null;
    }

    final lowerUrl = rawUrl.toLowerCase();
    if (lowerUrl.contains('://') &&
        !lowerUrl.startsWith('http://') &&
        !lowerUrl.startsWith('https://')) {
      return null;
    }
    if (!lowerUrl.startsWith('http://') && !lowerUrl.startsWith('https://')) {
      rawUrl = 'https://$rawUrl';
    }

    while (rawUrl.endsWith('/')) {
      rawUrl = rawUrl.substring(0, rawUrl.length - 1);
    }

    final baseUri = Uri.tryParse(rawUrl);
    if (baseUri == null ||
        (baseUri.scheme != 'http' && baseUri.scheme != 'https') ||
        baseUri.host.isEmpty ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment ||
        _hasInvalidPathSegments(baseUri.pathSegments)) {
      return null;
    }

    final trimmedFile = filePath.trim();
    if (_hasInvalidRemoteFilePath(trimmedFile)) {
      return null;
    }
    final cleanFile = trimmedFile.isEmpty
        ? defaultFileName
        : trimmedFile.replaceFirst(_leadingSlashesPattern, '');

    final encodedFileSegments = cleanFile
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    if (encodedFileSegments.isEmpty) {
      return null;
    }

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

  /// Resolves the sibling WebDAV endpoint [Uri] for [logFileName] next to the `.tdf` file.
  Uri resolveLogEndpointUri(String logFileName) {
    final trimmed = logFileName.trim();
    if (!_isValidLogFileName(trimmed)) {
      throw FormatException('Invalid diagnostic log file name: "$logFileName"');
    }
    final endpointUri = resolveEndpointUri();
    if (endpointUri == null || endpointUri.pathSegments.isEmpty) {
      throw const FormatException(
        'Cannot resolve WebDAV log endpoint URI from unconfigured server URL.',
      );
    }
    final parentSegments = endpointUri.pathSegments.sublist(
      0,
      endpointUri.pathSegments.length - 1,
    );
    return endpointUri.replace(
      pathSegments: <String>[...parentSegments, trimmed],
    );
  }

  /// Resolves the active [TdfTimeZoneContext] for [timeZoneMode] (`systemLocal()` or manual `fixedOffset`).
  TdfTimeZoneContext resolveTimeZoneContext() {
    return switch (timeZoneMode) {
      AppTimeZoneMode.automatic => const TdfTimeZoneContext.systemLocal(),
      AppTimeZoneMode.manual => TdfTimeZoneContext.fixedOffset(
        Duration(minutes: manualTimeZoneOffsetMinutes),
      ),
    };
  }

  /// Converts [instant] into a wall-clock [DateTime] (encoded with `isUtc: true` components
  /// for deterministic field access) according to [timeZoneMode] and [manualTimeZoneOffsetMinutes].
  DateTime toLocalWallClock(DateTime instant) {
    return resolveTimeZoneContext().toLocalWallClock(instant);
  }

  /// Returns `true` when [value] contains ASCII control characters or null bytes.
  static bool _hasControlCharacters(String value) {
    for (var i = 0; i < value.length; i++) {
      final code = value.codeUnitAt(i);
      if (code < 0x20 || code == 0x7F) {
        return true;
      }
    }
    return false;
  }

  /// Returns `true` when [segments] contains `.` or `..` traversal components.
  static bool _hasInvalidPathSegments(Iterable<String> segments) {
    for (final segment in segments) {
      if (segment == '.' || segment == '..') {
        return true;
      }
    }
    return false;
  }

  /// Returns `true` when [rawFilePath] contains backslashes, control characters, or traversal segments.
  static bool _hasInvalidRemoteFilePath(String rawFilePath) {
    if (rawFilePath.isEmpty) {
      return false;
    }
    if (rawFilePath.contains(r'\') || _hasControlCharacters(rawFilePath)) {
      return true;
    }
    return _hasInvalidPathSegments(rawFilePath.split('/'));
  }

  /// Returns `true` when [name] is a safe `.log` basename without path traversal.
  static bool _isValidLogFileName(String name) {
    if (name.length < 5 || !name.endsWith('.log') || name.contains('..')) {
      return false;
    }
    for (var i = 0; i < name.length; i++) {
      final code = name.codeUnitAt(i);
      if (code <= 0x20 || code >= 0x7F || code == 0x2F || code == 0x5C) {
        return false;
      }
    }
    return true;
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
        other.manualTimeZoneOffsetMinutes == manualTimeZoneOffsetMinutes &&
        other.diagnosticsEnabled == diagnosticsEnabled &&
        other.logLevel == logLevel &&
        other.logStorageMode == logStorageMode &&
        other.localWatchEnabled == localWatchEnabled &&
        other.dueLeadWindow == dueLeadWindow;
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
    diagnosticsEnabled,
    logLevel,
    logStorageMode,
    localWatchEnabled,
    dueLeadWindow,
  );

  @override
  String toString() =>
      'WebDavConfig(serverUrl: $serverUrl, username: $username, '
      'password: ${password.isEmpty ? "" : "[REDACTED]"}, '
      'filePath: $filePath, localFilePath: $localFilePath, '
      'storageMode: ${storageMode.name}, '
      'dueLeadWindow: ${dueLeadWindow.name})';
}
