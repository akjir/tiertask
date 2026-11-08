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

import 'package:flutter/services.dart';

import '../services/app_logger.dart';

/// Contract for loading and formatting the application version and SemVer 2.0.0 Git build metadata.
abstract interface class AppVersionRepository {
  /// Default fallback version string when Git build metadata is unavailable (`v0.1.0+0.unknown`).
  static const String defaultFullVersion = 'v$packageVersion+0.unknown';

  /// Fixed SemVer 2.0.0 package version for TierTask.
  static const String packageVersion = '0.1.0';

  /// Maximum allowed length for a formatted full version string.
  static const int _maxVersionLength = 64;

  /// Formats the full SemVer 2.0.0 application version with Git build metadata (`v<version>+<count>.<hash>[.dev]`).
  static String formatFullVersion({
    String packageVersion = AppVersionRepository.packageVersion,
    String? commitCount,
    String? commitHash,
    bool isDirty = false,
  }) {
    final cleanCount = _sanitizeCommitCount(commitCount);
    final cleanHash = _sanitizeCommitHash(commitHash);
    final suffix = isDirty ? '.dev' : '';
    return 'v$packageVersion+$cleanCount.$cleanHash$suffix';
  }

  /// Returns `true` when [value] is a single-line `v<version>+<metadata>` string without control characters.
  static bool isValidFullVersion(String value) {
    if (value.isEmpty || value.length > _maxVersionLength) {
      return false;
    }
    if (!value.startsWith('v') || !value.contains('+')) {
      return false;
    }
    for (var i = 0; i < value.length; i++) {
      final code = value.codeUnitAt(i);
      if (code <= 0x20 || code >= 0x7F) {
        return false;
      }
    }
    return true;
  }

  /// Loads the formatted application version string (`v0.1.0+<count>.<hash>[.dev]`).
  Future<String> loadAppVersion();

  /// Returns `true` when [value] is non-empty and consists strictly of ASCII digits (`0-9`).
  static bool _isAsciiDigits(String value) {
    if (value.isEmpty) {
      return false;
    }
    for (var i = 0; i < value.length; i++) {
      final code = value.codeUnitAt(i);
      if (code < 0x30 || code > 0x39) {
        return false;
      }
    }
    return true;
  }

  /// Returns `true` when [value] is non-empty and consists strictly of ASCII hexadecimal characters (`0-9`, `a-f`, `A-F`).
  static bool _isAsciiHex(String value) {
    if (value.isEmpty) {
      return false;
    }
    for (var i = 0; i < value.length; i++) {
      final code = value.codeUnitAt(i);
      final isDigit = code >= 0x30 && code <= 0x39;
      final isUpperHex = code >= 0x41 && code <= 0x46;
      final isLowerHex = code >= 0x61 && code <= 0x66;
      if (!isDigit && !isUpperHex && !isLowerHex) {
        return false;
      }
    }
    return true;
  }

  /// Validates and trims [rawCount], returning `'0'` when empty or non-numeric.
  static String _sanitizeCommitCount(String? rawCount) {
    if (rawCount == null) {
      return '0';
    }
    final trimmed = rawCount.trim();
    if (!_isAsciiDigits(trimmed)) {
      return '0';
    }
    return trimmed;
  }

  /// Validates and trims [rawHash], returning `'unknown'` when empty or non-hexadecimal.
  static String _sanitizeCommitHash(String? rawHash) {
    if (rawHash == null) {
      return 'unknown';
    }
    final trimmed = rawHash.trim();
    if (!_isAsciiHex(trimmed)) {
      return 'unknown';
    }
    return trimmed;
  }
}

/// In-memory [AppVersionRepository] implementation for deterministic unit and widget tests.
class FakeAppVersionRepository implements AppVersionRepository {
  /// Creates a [FakeAppVersionRepository] returning [version].
  const FakeAppVersionRepository({
    this.version = AppVersionRepository.defaultFullVersion,
  });

  /// Configured version string returned by [loadAppVersion].
  final String version;

  @override
  Future<String> loadAppVersion() async => version;
}

/// Platform-channel [AppVersionRepository] retrieving compile-time Git build metadata on Linux, Windows, and Android.
class PlatformAppVersionRepository implements AppVersionRepository {
  /// Creates a [PlatformAppVersionRepository] with an optional custom [channel].
  const PlatformAppVersionRepository({MethodChannel? channel})
    : _channel = channel ?? appVersionChannel;

  /// Native method channel for querying the compile-time application version.
  static const MethodChannel appVersionChannel = MethodChannel(
    'de.akjir.tiertask/app_version',
  );

  /// Optional compile-time override supplied via `--dart-define=TIERTASK_FULL_VERSION=...`.
  static const String _compileTimeVersion = String.fromEnvironment(
    'TIERTASK_FULL_VERSION',
  );

  final MethodChannel _channel;

  @override
  Future<String> loadAppVersion() async {
    final trimmedOverride = _compileTimeVersion.trim();
    if (AppVersionRepository.isValidFullVersion(trimmedOverride)) {
      AppLogger.debug(
        LogTag.lifecycle,
        'Resolved compile-time app version: $trimmedOverride',
      );
      return trimmedOverride;
    }
    try {
      final rawVersion = await _channel.invokeMethod<String>('getAppVersion');
      if (rawVersion != null) {
        final trimmed = rawVersion.trim();
        if (AppVersionRepository.isValidFullVersion(trimmed)) {
          AppLogger.debug(
            LogTag.lifecycle,
            'Resolved native channel app version: $trimmed',
          );
          return trimmed;
        }
      }
      AppLogger.warn(
        LogTag.lifecycle,
        'Native app version channel returned invalid value; using fallback ${AppVersionRepository.defaultFullVersion}',
      );
      return AppVersionRepository.defaultFullVersion;
    } on PlatformException catch (error) {
      AppLogger.warn(
        LogTag.lifecycle,
        'PlatformException reading app version (${error.code}); using fallback ${AppVersionRepository.defaultFullVersion}',
      );
      return AppVersionRepository.defaultFullVersion;
    } on MissingPluginException {
      return AppVersionRepository.defaultFullVersion;
    }
  }
}
