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
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/repositories/link_launcher_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlatformLinkLauncherRepository & FakeLinkLauncherRepository', () {
    String? lastLaunchedUri;
    var channelResult = true;
    var shouldThrowPlatformException = false;

    setUp(() {
      lastLaunchedUri = null;
      channelResult = true;
      shouldThrowPlatformException = false;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            PlatformLinkLauncherRepository.linkLauncherChannel,
            (call) async {
              if (call.method == 'openLink') {
                if (shouldThrowPlatformException) {
                  throw PlatformException(
                    code: 'LAUNCH_FAILED',
                    message: 'No application registered for URI',
                  );
                }
                final arguments = call.arguments;
                if (arguments is Map<Object?, Object?>) {
                  final rawUri = arguments['uri'];
                  if (rawUri is String) {
                    lastLaunchedUri = rawUri;
                  }
                }
                return channelResult;
              }
              return null;
            },
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            PlatformLinkLauncherRepository.linkLauncherChannel,
            null,
          );
    });

    test('dispatches valid URI to native method channel', () async {
      const repository = PlatformLinkLauncherRepository();
      await repository.openLink('  https://example.com/docs?v=1  ');
      expect(
        lastLaunchedUri,
        equals('https://example.com/docs?v=1'),
        reason: 'Trimmed valid URI must be sent to native openLink channel',
      );
    });

    test('rejects invalid schemes, control characters, and overlong URIs before calling platform channel', () async {
      const repository = PlatformLinkLauncherRepository();
      final overlongUri = 'https://example.com/${'a' * TaskLink.maxUriLength}';

      for (final invalidUri in [
        '',
        '   ',
        'example.com/no-scheme',
        '123://bad-scheme',
        'https://example.com/bad\nchar',
        'https://example.com/bad\x00null',
        overlongUri,
      ]) {
        await expectLater(
          () => repository.openLink(invalidUri),
          throwsA(isA<LinkLaunchException>()),
          reason: 'Invalid URI "$invalidUri" must throw LinkLaunchException',
        );
      }
      expect(
        lastLaunchedUri,
        isNull,
        reason: 'Invalid URIs must never reach the native platform channel',
      );
    });

    test('throws LinkLaunchException when native channel returns false or throws PlatformException', () async {
      const repository = PlatformLinkLauncherRepository();
      channelResult = false;
      await expectLater(
        () => repository.openLink('https://example.com'),
        throwsA(isA<LinkLaunchException>()),
        reason: 'Channel returning false must throw LinkLaunchException',
      );

      channelResult = true;
      shouldThrowPlatformException = true;
      await expectLater(
        () => repository.openLink('https://example.com'),
        throwsA(
          isA<LinkLaunchException>().having(
            (error) => error.cause,
            'cause',
            isA<PlatformException>(),
          ),
        ),
        reason: 'PlatformException must be wrapped in LinkLaunchException preserving cause',
      );
    });

    test('FakeLinkLauncherRepository records launched URIs and supports failure simulation', () async {
      final fake = FakeLinkLauncherRepository();
      await fake.openLink('mailto:ops@example.com');
      expect(fake.launchedUris, equals(['mailto:ops@example.com']));

      fake.shouldThrow = true;
      await expectLater(
        () => fake.openLink('https://example.com'),
        throwsA(isA<LinkLaunchException>()),
      );
    });
  });
}
