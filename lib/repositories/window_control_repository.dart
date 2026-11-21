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

/// In-memory [WindowControlRepository] implementation for deterministic unit and widget tests.
class FakeWindowControlRepository implements WindowControlRepository {
  /// Creates a [FakeWindowControlRepository].
  FakeWindowControlRepository();

  /// Number of [closeWindow] calls recorded.
  int closeWindowCount = 0;

  /// Number of [startDragging] calls recorded.
  int startDraggingCount = 0;

  /// Number of [toggleMaximize] calls recorded.
  int toggleMaximizeCount = 0;

  @override
  Future<void> closeWindow() async {
    closeWindowCount++;
  }

  @override
  Future<void> startDragging() async {
    startDraggingCount++;
  }

  @override
  Future<void> toggleMaximize() async {
    toggleMaximizeCount++;
  }
}

/// Platform-channel [WindowControlRepository] driving frameless desktop windows on Linux and Windows.
class PlatformWindowControlRepository implements WindowControlRepository {
  /// Creates a [PlatformWindowControlRepository] with an optional custom [channel].
  const PlatformWindowControlRepository({MethodChannel? channel})
    : _channel = channel ?? windowControlsChannel;

  /// Native method channel for desktop window drag, maximize, and close commands.
  static const MethodChannel windowControlsChannel = MethodChannel(
    'de.akjir.tiertask/window_controls',
  );

  final MethodChannel _channel;

  @override
  Future<void> closeWindow() =>
      _invokeCommand('closeWindow', level: LogLevel.info);

  @override
  Future<void> startDragging() =>
      _invokeCommand('startDragging', level: LogLevel.debug);

  @override
  Future<void> toggleMaximize() =>
      _invokeCommand('toggleMaximize', level: LogLevel.debug);

  /// Invokes [method] on [_channel], recording structured lifecycle telemetry and absorbing platform errors.
  Future<void> _invokeCommand(String method, {required LogLevel level}) async {
    try {
      final handled = await _channel.invokeMethod<bool>(method);
      if (AppLogger.shouldLog(level)) {
        AppLogger.event(
          level,
          LogTag.lifecycle,
          'window.control',
          fields: <String, Object?>{
            'command': method,
            'handled': handled ?? false,
          },
        );
      }
    } on PlatformException catch (error) {
      AppLogger.event(
        LogLevel.warn,
        LogTag.lifecycle,
        'window.control',
        fields: <String, Object?>{'command': method},
        error: error.code,
      );
    } on MissingPluginException {
      if (AppLogger.shouldLog(LogLevel.debug)) {
        AppLogger.event(
          LogLevel.debug,
          LogTag.lifecycle,
          'window.control',
          fields: <String, Object?>{
            'command': method,
            'reason': 'missing_plugin',
          },
        );
      }
    }
  }
}

/// Contract for desktop window actions on custom-decorated Linux and Windows shells.
abstract interface class WindowControlRepository {
  /// Requests a graceful close of the host desktop window.
  Future<void> closeWindow();

  /// Begins an OS-native interactive window move drag from the active primary pointer press.
  Future<void> startDragging();

  /// Toggles the host desktop window between maximized and restored states.
  Future<void> toggleMaximize();
}
