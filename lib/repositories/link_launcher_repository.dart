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

import '../models/task_item.dart';
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
    final trimmed = uri.trim();
    if (!TaskLink.isValidUri(trimmed)) {
      throw const LinkLaunchException('Invalid link URI.');
    }
    if (shouldThrow) {
      throw const LinkLaunchException('Simulated link launch failure.');
    }
    launchedUris.add(trimmed);
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
  /// Opens [uri] in the operating system's default application or handler.
  Future<void> openLink(String uri);
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

  final MethodChannel _channel;

  @override
  Future<void> openLink(String uri) async {
    final trimmed = uri.trim();
    final colonIndex = trimmed.indexOf(':');
    final scheme = colonIndex > 0
        ? trimmed.substring(0, colonIndex).toLowerCase()
        : 'unknown';
    if (!TaskLink.isValidUri(trimmed)) {
      AppLogger.event(
        LogLevel.error,
        LogTag.storage,
        'link.open',
        fields: <String, Object?>{'scheme': scheme, 'reason': 'invalid_uri'},
      );
      throw const LinkLaunchException('Invalid link URI.');
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
}
