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
import 'package:tiertask/models/storage_file_read_status.dart';

void main() {
  test('StorageFileReadStatus exposes readability flags, equality, and string representation for every state', () {
    const localOk = StorageFileReadStatus.readable(StorageFileTarget.local);
    const remoteUnsupported = StorageFileReadStatus.unsupportedVersion(
      StorageFileTarget.remote,
      version: '0.9.0',
    );
    const localUnreadable = StorageFileReadStatus.unreadable(
      StorageFileTarget.local,
      detail: 'Unclosed block.',
      line: 4,
    );

    expect(localOk.state, equals(StorageFileReadState.readable));
    expect(localOk.isReadable, isTrue);
    expect(localOk.isUnsupportedVersion, isFalse);
    expect(localOk.detail, isNull);
    expect(localOk.line, isNull);
    expect(localOk.unsupportedVersion, isNull);

    expect(
      remoteUnsupported.state,
      equals(StorageFileReadState.unsupportedVersion),
    );
    expect(remoteUnsupported.isReadable, isFalse);
    expect(remoteUnsupported.isUnsupportedVersion, isTrue);
    expect(remoteUnsupported.unsupportedVersion, equals('0.9.0'));

    expect(localUnreadable.state, equals(StorageFileReadState.unreadable));
    expect(localUnreadable.isReadable, isFalse);
    expect(localUnreadable.isUnsupportedVersion, isFalse);
    expect(localUnreadable.detail, equals('Unclosed block.'));
    expect(localUnreadable.line, equals(4));

    expect(
      localUnreadable,
      equals(
        const StorageFileReadStatus.unreadable(
          StorageFileTarget.local,
          detail: 'Unclosed block.',
          line: 4,
        ),
      ),
    );
    expect(
      localUnreadable.hashCode,
      equals(
        const StorageFileReadStatus.unreadable(
          StorageFileTarget.local,
          detail: 'Unclosed block.',
          line: 4,
        ).hashCode,
      ),
    );
    expect(localOk, isNot(equals(remoteUnsupported)));
    expect(remoteUnsupported.toString(), contains('remote'));
    expect(remoteUnsupported.toString(), contains('unsupportedVersion'));
  });

  test('StorageFileReadReport classifies every single-target and dual-target failure scope exhaustively', () {
    const localOk = StorageFileReadStatus.readable(StorageFileTarget.local);
    const remoteOk = StorageFileReadStatus.readable(StorageFileTarget.remote);
    final localCause = StateError('local cause');
    final remoteCause = StateError('remote cause');
    final localFail = StorageFileReadStatus.unreadable(
      StorageFileTarget.local,
      detail: 'Permission denied',
      cause: localCause,
    );
    final remoteFail = StorageFileReadStatus.unreadable(
      StorageFileTarget.remote,
      detail: 'Network unreachable',
      cause: remoteCause,
    );

    final cases =
        <
          ({
            String name,
            StorageFileReadReport report,
            StorageReadFailureScope? expectedScope,
            bool expectedBoth,
            int expectedEntryCount,
            Object? expectedCause,
          })
        >[
          (
            name: 'local-only readable',
            report: const StorageFileReadReport(local: localOk),
            expectedScope: null,
            expectedBoth: false,
            expectedEntryCount: 1,
            expectedCause: null,
          ),
          (
            name: 'remote-only readable',
            report: const StorageFileReadReport(remote: remoteOk),
            expectedScope: null,
            expectedBoth: false,
            expectedEntryCount: 1,
            expectedCause: null,
          ),
          (
            name: 'dual-storage both readable',
            report: const StorageFileReadReport(
              local: localOk,
              remote: remoteOk,
            ),
            expectedScope: null,
            expectedBoth: true,
            expectedEntryCount: 2,
            expectedCause: null,
          ),
          (
            name: 'local-only unreadable',
            report: StorageFileReadReport(local: localFail),
            expectedScope: StorageReadFailureScope.localOnly,
            expectedBoth: false,
            expectedEntryCount: 1,
            expectedCause: localCause,
          ),
          (
            name: 'remote-only unreadable',
            report: StorageFileReadReport(remote: remoteFail),
            expectedScope: StorageReadFailureScope.remoteOnly,
            expectedBoth: false,
            expectedEntryCount: 1,
            expectedCause: remoteCause,
          ),
          (
            name: 'dual-storage local failed remote ok',
            report: StorageFileReadReport(local: localFail, remote: remoteOk),
            expectedScope: StorageReadFailureScope.localFailedRemoteOk,
            expectedBoth: true,
            expectedEntryCount: 2,
            expectedCause: localCause,
          ),
          (
            name: 'dual-storage remote failed local ok',
            report: StorageFileReadReport(local: localOk, remote: remoteFail),
            expectedScope: StorageReadFailureScope.remoteFailedLocalOk,
            expectedBoth: true,
            expectedEntryCount: 2,
            expectedCause: remoteCause,
          ),
          (
            name: 'dual-storage both failed',
            report: StorageFileReadReport(local: localFail, remote: remoteFail),
            expectedScope: StorageReadFailureScope.bothFailed,
            expectedBoth: true,
            expectedEntryCount: 2,
            expectedCause: localCause,
          ),
        ];

    for (final testCase in cases) {
      expect(
        testCase.report.failureScope,
        equals(testCase.expectedScope),
        reason: 'Unexpected failureScope for ${testCase.name}',
      );
      expect(
        testCase.report.hasFailure,
        equals(testCase.expectedScope != null),
        reason: 'Unexpected hasFailure for ${testCase.name}',
      );
      expect(
        testCase.report.evaluatesBoth,
        equals(testCase.expectedBoth),
        reason: 'Unexpected evaluatesBoth for ${testCase.name}',
      );
      expect(
        testCase.report.activeEntries.length,
        equals(testCase.expectedEntryCount),
        reason: 'Unexpected activeEntries length for ${testCase.name}',
      );
      expect(
        testCase.report.primaryCause,
        same(testCase.expectedCause),
        reason: 'Unexpected primaryCause for ${testCase.name}',
      );
    }

    final bothReport = StorageFileReadReport(
      local: localFail,
      remote: remoteFail,
    );
    expect(bothReport.activeEntries.first.target, StorageFileTarget.local);
    expect(bothReport.activeEntries.last.target, StorageFileTarget.remote);
    expect(
      () => bothReport.activeEntries.add(localOk),
      throwsUnsupportedError,
      reason: 'activeEntries must return an unmodifiable list',
    );
  });

  test('StorageFileReadReport computes unsupportedVersionLabel across single, identical, differing, and mixed failures', () {
    const localV07 = StorageFileReadStatus.unsupportedVersion(
      StorageFileTarget.local,
      version: '0.7.0',
    );
    const remoteV07 = StorageFileReadStatus.unsupportedVersion(
      StorageFileTarget.remote,
      version: '0.7.0',
    );
    const remoteV09 = StorageFileReadStatus.unsupportedVersion(
      StorageFileTarget.remote,
      version: '0.9.0',
    );
    const remoteNetworkError = StorageFileReadStatus.unreadable(
      StorageFileTarget.remote,
      detail: 'Network error',
    );
    const localOk = StorageFileReadStatus.readable(StorageFileTarget.local);

    const sameBoth = StorageFileReadReport(local: localV07, remote: remoteV07);
    expect(sameBoth.hasUnsupportedVersion, isTrue);
    expect(sameBoth.unsupportedVersionLabel, equals('0.7.0'));

    const differingBoth = StorageFileReadReport(
      local: localV07,
      remote: remoteV09,
    );
    expect(differingBoth.hasUnsupportedVersion, isTrue);
    expect(differingBoth.unsupportedVersionLabel, equals('0.7.0 / 0.9.0'));

    const mixedUnsupportedAndIo = StorageFileReadReport(
      local: localV07,
      remote: remoteNetworkError,
    );
    expect(mixedUnsupportedAndIo.hasUnsupportedVersion, isTrue);
    expect(mixedUnsupportedAndIo.unsupportedVersionLabel, equals('0.7.0'));

    const localOkRemoteUnsupported = StorageFileReadReport(
      local: localOk,
      remote: remoteV09,
    );
    expect(localOkRemoteUnsupported.hasUnsupportedVersion, isTrue);
    expect(localOkRemoteUnsupported.unsupportedVersionLabel, equals('0.9.0'));

    const nonVersionFailure = StorageFileReadReport(
      local: localOk,
      remote: remoteNetworkError,
    );
    expect(nonVersionFailure.hasUnsupportedVersion, isFalse);
    expect(nonVersionFailure.unsupportedVersionLabel, isNull);

    expect(
      differingBoth,
      equals(const StorageFileReadReport(local: localV07, remote: remoteV09)),
    );
    expect(
      differingBoth.hashCode,
      equals(
        const StorageFileReadReport(
          local: localV07,
          remote: remoteV09,
        ).hashCode,
      ),
    );
  });
}
