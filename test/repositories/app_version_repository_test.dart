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
import 'package:tiertask/repositories/app_version_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppVersionRepository', () {
    String? channelVersionResult;
    var shouldThrowPlatformException = false;

    setUp(() {
      channelVersionResult = 'v0.1.0+55.e64e6a5';
      shouldThrowPlatformException = false;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            PlatformAppVersionRepository.appVersionChannel,
            (call) async {
              if (call.method == 'getAppVersion') {
                if (shouldThrowPlatformException) {
                  throw PlatformException(
                    code: 'VERSION_ERROR',
                    message: 'Failed to read native version',
                  );
                }
                return channelVersionResult;
              }
              return null;
            },
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            PlatformAppVersionRepository.appVersionChannel,
            null,
          );
    });

    test(
      'formatFullVersion matches Podoxide SemVer 2.0.0 build metadata rules',
      () {
        expect(
          AppVersionRepository.packageVersion,
          equals('0.1.0'),
          reason: 'Package version must be fixed to 0.1.0',
        );
        expect(
          AppVersionRepository.defaultFullVersion,
          equals('v0.1.0+0.unknown'),
          reason: 'Default fallback version must match Podoxide fallback',
        );
        expect(
          AppVersionRepository.formatFullVersion(
            commitCount: '55',
            commitHash: 'e64e6a5',
            isDirty: false,
          ),
          equals('v0.1.0+55.e64e6a5'),
          reason: 'Clean working tree must format without .dev suffix',
        );
        expect(
          AppVersionRepository.formatFullVersion(
            commitCount: '55',
            commitHash: 'e64e6a5',
            isDirty: true,
          ),
          equals('v0.1.0+55.e64e6a5.dev'),
          reason: 'Dirty working tree must append .dev suffix',
        );
      },
    );

    test('formatFullVersion sanitizes invalid commit counts and hashes to 0 and unknown', () {
      for (final invalidCount in <String?>[
        null,
        '',
        '   ',
        '-1',
        '12a',
        '12.3',
      ]) {
        expect(
          AppVersionRepository.formatFullVersion(
            commitCount: invalidCount,
            commitHash: 'abc1234',
          ),
          equals('v0.1.0+0.abc1234'),
          reason:
              'Non-digit or empty commit count "$invalidCount" must fall back to 0',
        );
      }

      for (final invalidHash in <String?>[
        null,
        '',
        '   ',
        'bad hash',
        'bad\nhash',
        'bad\x00hash',
        'G123456',
      ]) {
        expect(
          AppVersionRepository.formatFullVersion(
            commitCount: '42',
            commitHash: invalidHash,
          ),
          equals('v0.1.0+42.unknown'),
          reason:
              'Empty or non-hex commit hash "$invalidHash" must fall back to unknown',
        );
      }
    });

    test('PlatformAppVersionRepository returns valid channel version and falls back on invalid or failed responses', () async {
      const repository = PlatformAppVersionRepository();
      expect(
        await repository.loadAppVersion(),
        equals('v0.1.0+55.e64e6a5'),
        reason: 'Valid native channel response must be returned trimmed',
      );

      channelVersionResult = '  v0.1.0+56.1a2b3c4.dev  ';
      expect(
        await repository.loadAppVersion(),
        equals('v0.1.0+56.1a2b3c4.dev'),
        reason: 'Dirty build metadata from native channel must be accepted',
      );

      for (final malformed in <String?>[
        null,
        '',
        '   ',
        '0.1.0',
        'v0.1.0+\nmalformed',
      ]) {
        channelVersionResult = malformed;
        expect(
          await repository.loadAppVersion(),
          equals(AppVersionRepository.defaultFullVersion),
          reason:
              'Malformed native version "$malformed" must fall back to defaultFullVersion',
        );
      }

      shouldThrowPlatformException = true;
      expect(
        await repository.loadAppVersion(),
        equals(AppVersionRepository.defaultFullVersion),
        reason: 'PlatformException must fall back to defaultFullVersion',
      );
    });

    test(
      'FakeAppVersionRepository returns configured version string',
      () async {
        const fake = FakeAppVersionRepository(version: 'v0.1.0+99.deadbee.dev');
        expect(
          await fake.loadAppVersion(),
          equals('v0.1.0+99.deadbee.dev'),
          reason: 'FakeAppVersionRepository must return its configured version',
        );
      },
    );
  });
}
