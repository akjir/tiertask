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
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/presentation/window_control_controller.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/repositories/window_control_repository.dart';

void main() {
  group('WindowControlController', () {
    test('delegates closeWindow, startDragging, and toggleMaximize when desktop window controls are supported', () async {
      final fakeRepository = FakeWindowControlRepository();
      final container = ProviderContainer(
        overrides: [
          supportsDesktopWindowControlsProvider.overrideWithValue(true),
          windowControlRepositoryProvider.overrideWithValue(fakeRepository),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(windowControlControllerProvider);
      await controller.startDragging();
      await controller.toggleMaximize();
      await controller.closeWindow();

      expect(fakeRepository.startDraggingCount, equals(1));
      expect(fakeRepository.toggleMaximizeCount, equals(1));
      expect(fakeRepository.closeWindowCount, equals(1));
    });

    test('ignores all window commands when desktop window controls are unsupported (Android)', () async {
      final fakeRepository = FakeWindowControlRepository();
      final container = ProviderContainer(
        overrides: [
          supportsDesktopWindowControlsProvider.overrideWithValue(false),
          windowControlRepositoryProvider.overrideWithValue(fakeRepository),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(windowControlControllerProvider);
      await controller.startDragging();
      await controller.toggleMaximize();
      await controller.closeWindow();

      expect(fakeRepository.startDraggingCount, equals(0));
      expect(fakeRepository.toggleMaximizeCount, equals(0));
      expect(fakeRepository.closeWindowCount, equals(0));
    });
  });
}
