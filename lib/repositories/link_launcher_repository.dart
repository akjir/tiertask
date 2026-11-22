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

import '../models/tdf_metadata.dart';
import '../services/app_logger.dart';

/// In-memory [LinkLauncherRepository] implementation for deterministic unit and widget tests.
class FakeLinkLauncherRepository implements LinkLauncherRepository {
  /// Creates a [FakeLinkLauncherRepository] with optional [shouldThrow] state.
  FakeLinkLauncherRepository({this.shouldThrow = false});

  /// Recorded URIs passed to [openLink] in invocation order.
  final List<String> launchedUris = <String>[];

  /// Whether [openLink] should throw a [LinkLaunchException].
  bool shouldThrow;

  @override
  Future<void> openLink(String uri) async {
    if (!LinkLauncherRepository.isLaunchableUri(uri)) {
      throw const LinkLaunchException('Invalid or blocked link URI.');
    }
    if (shouldThrow) {
      throw const LinkLaunchException('Simulated link launch failure.');
    }
    launchedUris.add(uri.trim());
  }
}

/// Domain exception thrown when launching an external or internal task link URI fails.
class LinkLaunchException implements Exception {
  /// Creates a [LinkLaunchException] with [message] and optional [cause].
  const LinkLaunchException(this.message, {this.cause});

  /// Underlying platform or system exception cause when available.
  final Object? cause;

  /// Human-readable error message.
  final String message;

  @override
  String toString() => message;
}

/// Contract for launching task link URIs via the underlying operating system handler.
abstract interface class LinkLauncherRepository {
  static const Set<String> _blockedSchemes = <String>{
    'about',
    'blob',
    'cifs',
    'cmd',
    'content',
    'cscript',
    'data',
    'file',
    'hcp',
    'intent',
    'its',
    'jar',
    'javascript',
    'jscript',
    'livescript',
    'mhtml',
    'mk',
    'ms-appinstaller',
    'ms-msdt',
    'nfs',
    'powershell',
    'res',
    'search-ms',
    'shell',
    'smb',
    'vbscript',
    'view-source',
    'wscript',
  };

  /// Returns `true` when [rawUri] is a valid RFC 3986 URI with a multi-character
  /// scheme free of backslashes, control characters, Unicode BiDi/line controls,
  /// and blocked schemes.
  static bool isLaunchableUri(String rawUri) {
    if (_hasForbiddenLaunchChar(rawUri)) {
      return false;
    }
    final trimmed = rawUri.trim();
    if (!TaskLink.isValidUri(trimmed)) {
      return false;
    }
    final colonIndex = trimmed.indexOf(':');
    if (colonIndex < 2 || colonIndex >= trimmed.length - 1) {
      return false;
    }
    final scheme = trimmed.substring(0, colonIndex).toLowerCase();
    return !_blockedSchemes.contains(scheme);
  }

  /// Opens [uri] in the operating system's default application or handler.
  Future<void> openLink(String uri);

  /// Checks whether [rawUri] contains ASCII/C1 controls, backslashes, Arabic Letter Mark,
  /// Unicode line/paragraph separators, or Unicode BiDi override/isolate characters.
  static bool _hasForbiddenLaunchChar(String rawUri) {
    for (var i = 0; i < rawUri.length; i++) {
      final code = rawUri.codeUnitAt(i);
      if (code <= 0x1F ||
          code == 0x5C ||
          code == 0x7F ||
          (code >= 0x80 && code <= 0x9F) ||
          code == 0x061C ||
          code == 0x200E ||
          code == 0x200F ||
          (code >= 0x2028 && code <= 0x202E) ||
          (code >= 0x2066 && code <= 0x2069)) {
        return true;
      }
    }
    return false;
  }
}

/// Platform-channel [LinkLauncherRepository] invoking native OS URI handlers on Linux, Windows, and Android.
class PlatformLinkLauncherRepository implements LinkLauncherRepository {
  /// Creates a [PlatformLinkLauncherRepository] with an optional custom [channel].
  const PlatformLinkLauncherRepository({MethodChannel? channel})
    : _channel = channel ?? linkLauncherChannel;

  /// Native method channel for launching URIs across Linux, Windows, and Android.
  static const MethodChannel linkLauncherChannel = MethodChannel(
    'de.akjir.tiertask/link_launcher',
  );

  static const int _maxLoggedSchemeLength = 64;

  final MethodChannel _channel;

  @override
  Future<void> openLink(String uri) async {
    final trimmed = uri.trim();
    final scheme = _extractSafeSchemeForLogging(trimmed);
    if (!LinkLauncherRepository.isLaunchableUri(uri)) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        'link.open',
        fields: <String, Object?>{
          'scheme': scheme,
          'reason': 'blocked_or_invalid_uri',
        },
      );
      throw const LinkLaunchException('Invalid or blocked link URI.');
    }
    try {
      final launched = await _channel.invokeMethod<bool>(
        'openLink',
        <String, String>{'uri': trimmed},
      );
      if (launched != true) {
        AppLogger.event(
          LogLevel.error,
          LogTag.storage,
          'link.open',
          fields: <String, Object?>{'scheme': scheme, 'launched': false},
        );
        throw const LinkLaunchException('Could not open link URI.');
      }
      AppLogger.event(
        LogLevel.info,
        LogTag.storage,
        'link.open',
        fields: <String, Object?>{'scheme': scheme, 'launched': true},
      );
    } on PlatformException catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        'link.open',
        fields: <String, Object?>{'scheme': scheme},
        error: error.code,
      );
      throw LinkLaunchException(
        error.message ?? 'Could not open link URI.',
        cause: error,
      );
    } on MissingPluginException catch (error) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        'link.open',
        fields: <String, Object?>{'scheme': scheme, 'reason': 'missing_plugin'},
      );
      throw LinkLaunchException('Could not open link URI.', cause: error);
    }
  }

  /// Extracts a lowercase RFC 3986 URI scheme from [trimmed] for safe diagnostic logging,
  /// returning `'<invalid>'` when the prefix is malformed or oversized.
  static String _extractSafeSchemeForLogging(String trimmed) {
    final colonIndex = trimmed.indexOf(':');
    if (colonIndex < 2 || colonIndex > _maxLoggedSchemeLength) {
      return '<invalid>';
    }
    if (!_isAsciiAlpha(trimmed.codeUnitAt(0))) {
      return '<invalid>';
    }
    for (var i = 1; i < colonIndex; i++) {
      if (!_isSchemeContinuation(trimmed.codeUnitAt(i))) {
        return '<invalid>';
      }
    }
    return trimmed.substring(0, colonIndex).toLowerCase();
  }

  /// Returns `true` when [codeUnit] is an ASCII letter (`A-Z` or `a-z`).
  static bool _isAsciiAlpha(int codeUnit) =>
      (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
      (codeUnit >= 0x61 && codeUnit <= 0x7A);

  /// Returns `true` when [codeUnit] is an RFC 3986 scheme continuation character (`[A-Za-z0-9+.-]`).
  static bool _isSchemeContinuation(int codeUnit) =>
      _isAsciiAlpha(codeUnit) ||
      (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      codeUnit == 0x2B ||
      codeUnit == 0x2D ||
      codeUnit == 0x2E;
}
