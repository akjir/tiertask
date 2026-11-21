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

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/config_providers.dart';
import '../repositories/window_control_repository.dart';

/// Provides the presentation-layer [WindowControlController] for desktop custom chrome actions.
final windowControlControllerProvider = Provider<WindowControlController>(
  (ref) => WindowControlController(
    ref.watch(windowControlRepositoryProvider),
    isSupported: ref.watch(supportsDesktopWindowControlsProvider),
  ),
);

/// Mediates desktop custom-chrome window commands between `lib/ui_v2/` and [WindowControlRepository].
class WindowControlController {
  /// Creates a [WindowControlController] backed by [_repository] with [isSupported] platform gating.
  const WindowControlController(this._repository, {required this.isSupported});

  /// Whether the host platform enables custom desktop window controls (`true` on Linux and Windows, `false` on Android).
  final bool isSupported;

  final WindowControlRepository _repository;

  /// Requests a graceful application window close on supported desktop platforms.
  Future<void> closeWindow() async {
    if (!isSupported) {
      return;
    }
    await _repository.closeWindow();
  }

  /// Starts a native desktop window move drag on supported desktop platforms.
  Future<void> startDragging() async {
    if (!isSupported) {
      return;
    }
    await _repository.startDragging();
  }

  /// Toggles maximized/restored state on supported desktop platforms.
  Future<void> toggleMaximize() async {
    if (!isSupported) {
      return;
    }
    await _repository.toggleMaximize();
  }
}
