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
import 'package:tiertask/presentation/link_action_controller.dart';
import 'package:tiertask/providers/config_providers.dart';
import 'package:tiertask/repositories/link_launcher_repository.dart';

void main() {
  group('LinkActionController', () {
    test(
      'returns opened and records URI when repository launches valid link',
      () async {
        final fakeRepository = FakeLinkLauncherRepository();
        final container = ProviderContainer(
          overrides: [
            linkLauncherRepositoryProvider.overrideWithValue(fakeRepository),
          ],
        );
        addTearDown(container.dispose);

        final controller = container.read(linkActionControllerProvider);
        final outcome = await controller.openLink('https://example.com/docs');

        expect(outcome, equals(LinkOpenOutcome.opened));
        expect(
          fakeRepository.launchedUris,
          equals(['https://example.com/docs']),
        );
      },
    );

    test('returns failed on LinkLaunchException or invalid URI', () async {
      final fakeRepository = FakeLinkLauncherRepository(shouldThrow: true);
      final container = ProviderContainer(
        overrides: [
          linkLauncherRepositoryProvider.overrideWithValue(fakeRepository),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(linkActionControllerProvider);
      expect(
        await controller.openLink('https://example.com/docs'),
        equals(LinkOpenOutcome.failed),
      );

      fakeRepository.shouldThrow = false;
      const invalidUris = <String>[
        '',
        '   ',
        'not-a-uri',
        'javascript:alert(1)',
        'https://example.com/bad\nline',
      ];
      for (final uri in invalidUris) {
        expect(
          await controller.openLink(uri),
          equals(LinkOpenOutcome.failed),
          reason: 'Invalid URI should resolve to LinkOpenOutcome.failed: $uri',
        );
      }
      expect(fakeRepository.launchedUris, isEmpty);
    });
  });
}
