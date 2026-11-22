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

import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/app_build_profile.dart';

void main() {
  group('AppBuildProfile', () {
    test('maps every enum variant to distinct storage metadata and titles', () {
      for (final profile in AppBuildProfile.values) {
        switch (profile) {
          case AppBuildProfile.release:
            expect(
              profile.isDev,
              isFalse,
              reason: 'Release profile must not report isDev',
            );
            expect(
              profile.dataDirectoryName,
              equals('tiertask'),
              reason: 'Release data directory must remain tiertask',
            );
            expect(
              profile.webdavPasswordKeyPrefix,
              equals('t2_webdav_pw_'),
              reason: 'Release WebDAV password prefix must be t2_webdav_pw_',
            );
            expect(
              profile.syncStorageKeyPrefix,
              equals('t2_sync_v1_'),
              reason: 'Release sync prefix must remain t2_sync_v1_',
            );
            expect(
              profile.formatWindowTitle('TierTask'),
              equals('TierTask'),
              reason: 'Release window title must stay unmodified',
            );
          case AppBuildProfile.dev:
            expect(
              profile.isDev,
              isTrue,
              reason: 'Dev profile must report isDev',
            );
            expect(
              profile.dataDirectoryName,
              equals('tiertask-dev'),
              reason: 'Dev data directory must be isolated as tiertask-dev',
            );
            expect(
              profile.webdavPasswordKeyPrefix,
              equals('t2_dev_webdav_pw_'),
              reason: 'Dev WebDAV password prefix must be isolated as t2_dev_webdav_pw_',
            );
            expect(
              profile.syncStorageKeyPrefix,
              equals('t2_dev_sync_v1_'),
              reason: 'Dev sync prefix must be isolated as t2_dev_sync_v1_',
            );
            expect(
              profile.formatWindowTitle('TierTask'),
              equals('TierTask (Dev)'),
              reason: 'Dev window title must append (Dev)',
            );
        }
      }
    });

    test('resolve prioritizes explicit TIERTASK_ENV over kReleaseMode fallback', () {
      final cases = <({String raw, bool isRelease, AppBuildProfile expected})>[
        (raw: '', isRelease: true, expected: AppBuildProfile.release),
        (raw: '', isRelease: false, expected: AppBuildProfile.dev),
        (raw: 'dev', isRelease: true, expected: AppBuildProfile.dev),
        (raw: ' DEV ', isRelease: true, expected: AppBuildProfile.dev),
        (raw: 'release', isRelease: false, expected: AppBuildProfile.release),
        (raw: ' Release ', isRelease: false, expected: AppBuildProfile.release),
        (raw: 'staging', isRelease: true, expected: AppBuildProfile.release),
        (raw: 'unknown', isRelease: false, expected: AppBuildProfile.dev),
      ];

      for (final testCase in cases) {
        expect(
          AppBuildProfile.resolve(
            rawEnvironment: testCase.raw,
            isReleaseMode: testCase.isRelease,
          ),
          equals(testCase.expected),
          reason:
              'raw="${testCase.raw}", isRelease=${testCase.isRelease} must resolve to ${testCase.expected}',
        );
      }
    });

    test('current resolves to dev in non-release test mode by default', () {
      expect(AppBuildProfile.environmentKey, equals('TIERTASK_ENV'));
      if (AppBuildProfile.rawEnvironmentValue.trim().isEmpty) {
        expect(AppBuildProfile.current, equals(AppBuildProfile.dev));
      }
    });
  });
}
