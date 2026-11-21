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
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/repositories/window_control_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlatformWindowControlRepository & FakeWindowControlRepository', () {
    final invokedMethods = <String>[];
    var shouldThrowPlatformException = false;
    var throwMissingPlugin = false;

    setUp(() {
      invokedMethods.clear();
      shouldThrowPlatformException = false;
      throwMissingPlugin = false;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            PlatformWindowControlRepository.windowControlsChannel,
            (call) async {
              if (throwMissingPlugin) {
                throw MissingPluginException('No implementation found');
              }
              if (shouldThrowPlatformException) {
                throw PlatformException(
                  code: 'WINDOW_CONTROL_FAILED',
                  message: 'Simulated window control failure',
                );
              }
              invokedMethods.add(call.method);
              return true;
            },
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            PlatformWindowControlRepository.windowControlsChannel,
            null,
          );
    });

    test('dispatches closeWindow, startDragging, and toggleMaximize to native channel', () async {
      const repository = PlatformWindowControlRepository();
      await repository.startDragging();
      await repository.toggleMaximize();
      await repository.closeWindow();

      expect(
        invokedMethods,
        equals(<String>['startDragging', 'toggleMaximize', 'closeWindow']),
        reason: 'Each desktop window command must invoke its matching native method',
      );
    });

    test('absorbs PlatformException and MissingPluginException gracefully without throwing', () async {
      const repository = PlatformWindowControlRepository();
      shouldThrowPlatformException = true;
      await expectLater(repository.startDragging(), completes);
      await expectLater(repository.toggleMaximize(), completes);
      await expectLater(repository.closeWindow(), completes);

      shouldThrowPlatformException = false;
      throwMissingPlugin = true;
      await expectLater(repository.startDragging(), completes);
      await expectLater(repository.toggleMaximize(), completes);
      await expectLater(repository.closeWindow(), completes);
    });

    test('FakeWindowControlRepository counts all window commands', () async {
      final fake = FakeWindowControlRepository();
      await fake.startDragging();
      await fake.startDragging();
      await fake.toggleMaximize();
      await fake.closeWindow();

      expect(fake.startDraggingCount, equals(2));
      expect(fake.toggleMaximizeCount, equals(1));
      expect(fake.closeWindowCount, equals(1));
    });
  });
}
