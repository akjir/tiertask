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

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_payload_comparison.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/tdf_timezone.dart';
import 'package:tiertask/models/webdav_config.dart';

void main() {
  group('TDF 0.5.0 Proleptic Gregorian Calendar and Unicode Scalars', () {
    test('validates proleptic Gregorian calendar dates in 0001..9999 and rejects year 0000, > 9999, and non-leap century Feb 29', () {
      expect(
        TdfCalendar.isValidGregorianDate(1, 1, 1),
        isTrue,
        reason: '0001-01-01 is the minimum valid proleptic Gregorian date',
      );
      expect(
        TdfCalendar.isValidGregorianDate(9999, 12, 31),
        isTrue,
        reason: '9999-12-31 is the maximum valid proleptic Gregorian date',
      );
      expect(
        TdfCalendar.isValidGregorianDate(2000, 2, 29),
        isTrue,
        reason: '2000 is divisible by 400 and is a leap year',
      );
      expect(
        TdfCalendar.isValidGregorianDate(2024, 2, 29),
        isTrue,
        reason: '2024 is divisible by 4 and not 100 and is a leap year',
      );
      expect(
        TdfCalendar.isValidGregorianDate(1900, 2, 29),
        isFalse,
        reason: '1900 is divisible by 100 and not 400 and is not a leap year',
      );
      expect(
        TdfCalendar.isValidGregorianDate(0, 1, 1),
        isFalse,
        reason: 'Year 0000 is outside supported range 0001..9999',
      );
      expect(
        TdfCalendar.isValidGregorianDate(10000, 1, 1),
        isFalse,
        reason: 'Year 10000 is outside supported range 0001..9999',
      );
    });

    test('counts Unicode scalar values accurately for astral plane characters and rejects unpaired UTF-16 surrogates', () {
      expect(
        TdfCalendar.countUnicodeScalars('Hello'),
        equals(5),
        reason: 'ASCII characters count as 1 Unicode scalar each',
      );
      expect(
        TdfCalendar.countUnicodeScalars('A\u{1F600}B'),
        equals(3),
        reason:
            'Astral character U+1F600 (2 UTF-16 code units) counts as 1 scalar',
      );
      final fiveHundredAstral = '\u{1F600}' * 500;
      expect(
        fiveHundredAstral.length,
        equals(1000),
        reason: '500 astral characters occupy 1000 UTF-16 code units',
      );
      expect(
        TdfCalendar.countUnicodeScalars(fiveHundredAstral),
        equals(500),
        reason: '500 astral characters equal exactly 500 Unicode scalars',
      );
      final unpairedHigh = String.fromCharCodes(<int>[0x41, 0xD800, 0x42]);
      final unpairedLow = String.fromCharCodes(<int>[0x41, 0xDC00, 0x42]);
      expect(
        TdfCalendar.countUnicodeScalars(unpairedHigh),
        isNull,
        reason: 'Unpaired high surrogate must be rejected',
      );
      expect(
        TdfCalendar.countUnicodeScalars(unpairedLow),
        isNull,
        reason: 'Unpaired low surrogate must be rejected',
      );
    });

    test('validates TaskLink.isValidUri using Unicode scalar value count rather than UTF-16 code units', () {
      const prefix = 'https://example.com/';
      final valid2048Scalars = '$prefix${'\u{1F600}' * (2048 - prefix.length)}';
      expect(
        valid2048Scalars.length,
        greaterThan(TaskLink.maxUriLength),
        reason: 'Astral plane URI exceeds 2048 UTF-16 code units',
      );
      expect(
        TdfCalendar.countUnicodeScalars(valid2048Scalars),
        equals(TaskLink.maxUriLength),
      );
      expect(
        TaskLink.isValidUri(valid2048Scalars),
        isTrue,
        reason: 'URI with exactly 2048 Unicode scalar values must be valid',
      );

      final invalid2049Scalars = '$valid2048Scalars\u{1F600}';
      expect(
        TaskLink.isValidUri(invalid2049Scalars),
        isFalse,
        reason: 'URI with 2049 Unicode scalar values must be rejected',
      );
      expect(
        TaskLink.isValidUri('   '),
        isFalse,
        reason: 'ASCII space-only URI must be rejected',
      );
      expect(
        TaskLink.isValidUri('\t'),
        isFalse,
        reason: 'ASCII tab-only URI must be rejected',
      );
    });
  });

  group('TDF 0.5.0 TdfRepeatClock and Europe/Berlin Section 6.10.4 Vectors', () {
    test('parses and formats TdfRepeatClock in HH:MM and HH:MM:SS and rejects 24:00 or malformed values', () {
      expect(TdfRepeatClock.tryParse('00:00'), equals(TdfRepeatClock.midnight));
      expect(
        TdfRepeatClock.tryParse('00:00:00'),
        equals(TdfRepeatClock.midnight),
      );
      expect(
        TdfRepeatClock.midnight.formatCanonical(),
        isEmpty,
        reason: 'Midnight clock is omitted in canonical output',
      );
      final nineAm = TdfRepeatClock.tryParse('09:00');
      expect(nineAm, equals(const TdfRepeatClock(hour: 9)));
      expect(nineAm?.formatCanonical(), equals('09:00'));

      final withSeconds = TdfRepeatClock.tryParse('14:30:15');
      expect(
        withSeconds,
        equals(const TdfRepeatClock(hour: 14, minute: 30, second: 15)),
      );
      expect(withSeconds?.formatCanonical(), equals('14:30:15'));

      expect(TdfRepeatClock.tryParse('24:00'), isNull);
      expect(TdfRepeatClock.tryParse('24:00:00'), isNull);
      expect(TdfRepeatClock.tryParse('9:00'), isNull);
      expect(TdfRepeatClock.tryParse('09:60'), isNull);
      expect(TdfRepeatClock.tryParse('09:00:60'), isNull);
    });

    test('resolves all Section 6.10.4 Europe/Berlin conversion vectors including spring-forward gap and fall-back overlap', () {
      const zone = TdfTimeZoneContext.europeBerlin;

      expect(
        zone.resolveLocalToUtc(2026, 3, 28, 9, 0, 0),
        equals(DateTime.utc(2026, 3, 28, 8)),
        reason: '2026-03-28 09:00:00 CET (UTC+1) -> 2026-03-28 08:00:00 UTC',
      );
      expect(
        zone.resolveLocalToUtc(2026, 3, 29, 9, 0, 0),
        equals(DateTime.utc(2026, 3, 29, 7)),
        reason: '2026-03-29 09:00:00 CEST (UTC+2) -> 2026-03-29 07:00:00 UTC',
      );
      expect(
        zone.resolveLocalToUtc(2026, 3, 29, 2, 30, 0),
        equals(DateTime.utc(2026, 3, 29, 1, 30)),
        reason: '2026-03-29 02:30:00 falls in spring-forward gap -> pre-gap UTC+1 -> 01:30:00 UTC (03:30:00 CEST)',
      );
      expect(
        zone.toLocalWallClock(DateTime.utc(2026, 3, 29, 1, 30)),
        equals(DateTime.utc(2026, 3, 29, 3, 30)),
        reason:
            'Resolved 2026-03-29 01:30:00 UTC is 03:30:00 local after the gap',
      );
      expect(
        zone.resolveLocalToUtc(2026, 3, 30, 2, 30, 0),
        equals(DateTime.utc(2026, 3, 30, 0, 30)),
        reason: '2026-03-30 02:30:00 CEST (UTC+2) -> 2026-03-30 00:30:00 UTC',
      );
      expect(
        zone.resolveLocalToUtc(2026, 10, 25, 2, 30, 0),
        equals(DateTime.utc(2026, 10, 25, 0, 30)),
        reason: '2026-10-25 02:30:00 occurs twice during fall-back overlap -> first occurrence (UTC+2) -> 00:30:00 UTC',
      );
      expect(
        zone.resolveLocalToUtc(2026, 10, 25, 9, 0, 0),
        equals(DateTime.utc(2026, 10, 25, 8)),
        reason: '2026-10-25 09:00:00 CET (UTC+1) -> 2026-10-25 08:00:00 UTC',
      );
      expect(
        zone.resolveLocalToUtc(2026, 11, 5, 0, 0, 0),
        equals(DateTime.utc(2026, 11, 4, 23)),
        reason: '2026-11-05 00:00:00 CET (UTC+1) -> 2026-11-04 23:00:00 UTC',
      );
    });

    test('computes next due UTC instant for TaskRepeatRule across DST and month-end boundaries and enforces TimeZoneContextRequired', () {
      const dailyAt0230 = TaskRepeatRule(
        count: 1,
        unit: RepeatUnit.days,
        clock: TdfRepeatClock(hour: 2, minute: 30),
      );
      final completedOnMar28Utc = DateTime.utc(2026, 3, 28, 10);
      final nextDueGapUtc = dailyAt0230.nextDueUtc(
        completedAtUtc: completedOnMar28Utc,
        timeZone: TdfTimeZoneContext.europeBerlin,
      );
      expect(
        nextDueGapUtc,
        equals(DateTime.utc(2026, 3, 29, 1, 30)),
        reason: 'Completing on 2026-03-28 schedules 2026-03-29 02:30 local -> 01:30 UTC via pre-gap offset',
      );
      expect(
        dailyAt0230.clock,
        equals(const TdfRepeatClock(hour: 2, minute: 30)),
        reason: 'Repeat rule clock must remain 02:30 after gap adjustment',
      );

      final nextDueMar30Utc = dailyAt0230.nextDueUtc(
        completedAtUtc: DateTime.utc(2026, 3, 29, 10),
        timeZone: TdfTimeZoneContext.europeBerlin,
      );
      expect(
        nextDueMar30Utc,
        equals(DateTime.utc(2026, 3, 30, 0, 30)),
        reason: 'Completing on 2026-03-29 schedules 2026-03-30 02:30 CEST -> 00:30 UTC',
      );

      expect(
        () => dailyAt0230.nextDueUtc(
          completedAtUtc: completedOnMar28Utc,
          timeZone: const TdfTimeZoneContext.missing(),
        ),
        throwsA(
          isA<TdfContextException>().having(
            (error) => error.kind,
            'kind',
            TdfContextOutcomeKind.timeZoneContextRequired,
          ),
        ),
        reason: 'Missing timezone context must throw TimeZoneContextRequired',
      );
    });
  });

  group(
    'TDF 0.5.0 TaskDependency, DeletedBlock, QueueBlock, and Label Epoch',
    () {
      test('parses and formats TaskDependency (<task-id>[:<n>]) and deduplicates by retaining greatest requirement', () {
        final bare = TdfTaskDependency.tryParse('8jKaCdOkD2');
        expect(bare, isNotNull);
        expect(bare!.taskId, equals('8jKaCdOkD2'));
        expect(bare.requiredCompletion, equals(1));
        expect(
          bare.formatCanonical(),
          equals('8jKaCdOkD2'),
          reason: 'Required completion 1 omits :1 suffix in canonical output',
        );

        final withSuffix = TdfTaskDependency.tryParse('8jKaCdOkD2:8');
        expect(withSuffix, isNotNull);
        expect(withSuffix!.taskId, equals('8jKaCdOkD2'));
        expect(withSuffix.requiredCompletion, equals(8));
        expect(withSuffix.formatCanonical(), equals('8jKaCdOkD2:8'));

        expect(
          TdfTaskDependency.tryParse('8jKaCdOkD2:0'),
          isNull,
          reason: 'Required completion 0 is out of bounds 1..MAX_COMPLETIONS',
        );
        expect(
          TdfTaskDependency.tryParse('8jKaCdOkD2:9007199254740992'),
          isNull,
          reason:
              'Required completion > 9,007,199,254,740,991 is out of bounds',
        );
        expect(
          TdfTaskDependency.tryParse('bad_id:2'),
          isNull,
          reason: 'Non-canonical task ID must be rejected',
        );

        final deduplicated = TdfTaskDependency.normalizeList(<
          TdfTaskDependency
        >[
          const TdfTaskDependency(taskId: '8jKaCdOkD2', requiredCompletion: 2),
          const TdfTaskDependency(taskId: '3nQp7ROkB8'),
          const TdfTaskDependency(taskId: '8jKaCdOkD2', requiredCompletion: 5),
        ]);
        expect(
          deduplicated,
          equals(const <TdfTaskDependency>[
            TdfTaskDependency(taskId: '3nQp7ROkB8'),
            TdfTaskDependency(taskId: '8jKaCdOkD2', requiredCompletion: 5),
          ]),
          reason: 'Deduplication must retain greatest requirement and sort by ascending ASCII ID',
        );
      });

      test('unstamped TdfLabel effectiveModifiedAt defaults to Unix epoch 1970-01-01 00:00:00 UTC', () {
        const label = TdfLabel(id: '4x9p2mOkD2', name: 'Home');
        expect(
          label.effectiveModifiedAt,
          equals(DateTime.utc(1970)),
          reason: 'Section 6.7.2 requires unstamped labels to use 1970-01-01 00:00:00 UTC',
        );
      });
    },
  );

  group('QuickAddMode and TdfException Primitives', () {
    test('maps QuickAddMode to targetTier and formats TdfException diagnostic strings', () {
      expect(QuickAddMode.standard.targetTier, equals(TaskTier.planned));
      expect(QuickAddMode.priority.targetTier, equals(TaskTier.focus));
      expect(QuickAddMode.someday.targetTier, equals(TaskTier.someday));

      const parseErr = TdfException(
        kind: TdfErrorKind.invalidIdentifier,
        line: 12,
        message: 'Bad ID',
      );
      expect(
        parseErr.toString(),
        equals('TdfException(invalidIdentifier, line 12): Bad ID'),
      );
      expect(maxTdfBlocksPerDoc, equals(4096));
    });
  });

  group('WebDavConfig.localWatchEnabled Primitives', () {
    test('defaults localWatchEnabled to true and supports copyWith, equality, and hashCode', () {
      const defaultConfig = WebDavConfig();
      expect(
        defaultConfig.localWatchEnabled,
        isTrue,
        reason:
            'New WebDavConfig must enable local directory watching by default',
      );

      final disabled = defaultConfig.copyWith(localWatchEnabled: false);
      expect(disabled.localWatchEnabled, isFalse);
      expect(disabled, isNot(equals(defaultConfig)));
      expect(disabled.hashCode, isNot(equals(defaultConfig.hashCode)));

      final preservedDisabled = disabled.copyWith(
        themePalette: AppThemePalette.plumUmber,
      );
      expect(
        preservedDisabled.localWatchEnabled,
        isFalse,
        reason: 'copyWith without localWatchEnabled must preserve false',
      );

      final reEnabled = disabled.copyWith(localWatchEnabled: true);
      expect(reEnabled, equals(defaultConfig));
      expect(reEnabled.hashCode, equals(defaultConfig.hashCode));
    });

    test('exposes AppThemePalette calm and plumUmber with silent legacy slate/navy migration', () {
      expect(
        AppThemePalette.values,
        equals(const <AppThemePalette>[
          AppThemePalette.calm,
          AppThemePalette.plumUmber,
        ]),
      );
      expect(AppThemePalette.calm.jsonValue, equals('calm'));
      expect(AppThemePalette.plumUmber.jsonValue, equals('plum_umber'));
      expect(const WebDavConfig().themePalette, equals(AppThemePalette.calm));
      expect(
        AppThemePalette.tryParseJson('calm'),
        equals(AppThemePalette.calm),
      );
      expect(
        AppThemePalette.tryParseJson('plum_umber'),
        equals(AppThemePalette.plumUmber),
      );
      expect(
        AppThemePalette.tryParseJson('slate'),
        equals(AppThemePalette.calm),
        reason: 'Legacy "slate" token must migrate silently to calm',
      );
      expect(
        AppThemePalette.tryParseJson('navy'),
        equals(AppThemePalette.calm),
        reason: 'Legacy "navy" token must migrate silently to calm',
      );
      expect(AppThemePalette.tryParseJson('neon'), isNull);
    });

    test('exposes DueLeadWindow variants, jsonValue/tryParseJson, and WebDavConfig dueLeadWindow copyWith/equality/toString', () {
      expect(
        DueLeadWindow.values,
        equals(const <DueLeadWindow>[
          DueLeadWindow.off,
          DueLeadWindow.atDue,
          DueLeadWindow.hours12,
          DueLeadWindow.hours24,
          DueLeadWindow.hours48,
          DueLeadWindow.days7,
        ]),
        reason: 'DueLeadWindow must declare all 6 ordered horizon variants',
      );

      final expectedSpecs = <(DueLeadWindow, String, Duration?)>[
        (DueLeadWindow.off, 'off', null),
        (DueLeadWindow.atDue, 'at_due', Duration.zero),
        (DueLeadWindow.hours12, 'hours12', const Duration(hours: 12)),
        (DueLeadWindow.hours24, 'hours24', const Duration(hours: 24)),
        (DueLeadWindow.hours48, 'hours48', const Duration(hours: 48)),
        (DueLeadWindow.days7, 'days7', const Duration(days: 7)),
      ];
      for (final (window, expectedToken, expectedDuration) in expectedSpecs) {
        expect(
          window.jsonValue,
          equals(expectedToken),
          reason: '${window.name} jsonValue must equal "$expectedToken"',
        );
        expect(
          window.duration,
          equals(expectedDuration),
          reason: '${window.name} duration must equal $expectedDuration',
        );
        expect(
          DueLeadWindow.tryParseJson(expectedToken),
          equals(window),
          reason:
              'tryParseJson("$expectedToken") must resolve to ${window.name}',
        );
      }

      expect(
        DueLeadWindow.tryParseJson('unknown'),
        isNull,
        reason: 'Unknown token must return null from tryParseJson',
      );
      expect(
        DueLeadWindow.tryParseJson(null),
        isNull,
        reason: 'Null token must return null from tryParseJson',
      );

      const defaultConfig = WebDavConfig();
      expect(
        defaultConfig.dueLeadWindow,
        equals(DueLeadWindow.hours24),
        reason: 'WebDavConfig must default dueLeadWindow to 24 hours',
      );
      expect(
        defaultConfig.toString(),
        contains('dueLeadWindow: hours24'),
        reason: 'WebDavConfig.toString() must include dueLeadWindow name',
      );

      for (final variant in DueLeadWindow.values) {
        final updated = defaultConfig.copyWith(dueLeadWindow: variant);
        expect(
          updated.dueLeadWindow,
          equals(variant),
          reason: 'copyWith(dueLeadWindow: ${variant.name}) must apply variant',
        );
        if (variant == DueLeadWindow.hours24) {
          expect(updated, equals(defaultConfig));
          expect(updated.hashCode, equals(defaultConfig.hashCode));
        } else {
          expect(
            updated,
            isNot(equals(defaultConfig)),
            reason: '${variant.name} must differ from default hours24 config',
          );
          expect(updated.hashCode, isNot(equals(defaultConfig.hashCode)));
          final preserved = updated.copyWith(localWatchEnabled: false);
          expect(
            preserved.dueLeadWindow,
            equals(variant),
            reason:
                'copyWith without dueLeadWindow must preserve ${variant.name}',
          );
        }
      }
    });

    test('validates WebDAV server URLs with implicit https:// fallback and enforces exact parity with resolveEndpointUri', () {
      expect(
        WebDavServerUrlError.values,
        containsAll(const <WebDavServerUrlError>[
          WebDavServerUrlError.empty,
          WebDavServerUrlError.embeddedUserInfo,
          WebDavServerUrlError.invalid,
        ]),
      );

      const validCases = <({String input, String expectedEndpoint})>[
        (
          input: 'starknet.one',
          expectedEndpoint:
              'https://starknet.one/remote.php/dav/files/alice/test.tdf',
        ),
        (
          input: '  cloud.example.com  ',
          expectedEndpoint:
              'https://cloud.example.com/remote.php/dav/files/alice/test.tdf',
        ),
        (
          input: 'cloud.example.com:8443/nextcloud/',
          expectedEndpoint: 'https://cloud.example.com:8443/nextcloud/remote.php/dav/files/alice/test.tdf',
        ),
        (
          input: '[::1]:8443/dav',
          expectedEndpoint:
              'https://[::1]:8443/dav/remote.php/dav/files/alice/test.tdf',
        ),
        (
          input: '[2001:db8::1]',
          expectedEndpoint:
              'https://[2001:db8::1]/remote.php/dav/files/alice/test.tdf',
        ),
        (
          input: 'HTTP://127.0.0.1:8080',
          expectedEndpoint:
              'http://127.0.0.1:8080/remote.php/dav/files/alice/test.tdf',
        ),
        (
          input: 'HTTPS://cloud.example.com/remote.php/dav/files/alice/',
          expectedEndpoint:
              'https://cloud.example.com/remote.php/dav/files/alice/test.tdf',
        ),
      ];
      for (final testCase in validCases) {
        expect(
          WebDavConfig.validateServerUrl(testCase.input),
          isNull,
          reason: 'Expected valid serverUrl for "${testCase.input}"',
        );
        final config = WebDavConfig(
          serverUrl: testCase.input,
          username: 'alice',
          filePath: 'test.tdf',
        );
        expect(
          config.resolveEndpointUri()?.toString(),
          equals(testCase.expectedEndpoint),
          reason: 'Unexpected resolved endpoint for "${testCase.input}"',
        );
      }

      const invalidCases = <({String input, WebDavServerUrlError expected})>[
        (input: '', expected: WebDavServerUrlError.empty),
        (input: '   ', expected: WebDavServerUrlError.empty),
        (
          input: 'https://user:pass@cloud.example.com',
          expected: WebDavServerUrlError.embeddedUserInfo,
        ),
        (
          input: 'https://user@cloud.example.com',
          expected: WebDavServerUrlError.embeddedUserInfo,
        ),
        (
          input: 'https://@cloud.example.com',
          expected: WebDavServerUrlError.embeddedUserInfo,
        ),
        (
          input: 'user:pass@cloud.example.com',
          expected: WebDavServerUrlError.embeddedUserInfo,
        ),
        (
          input: 'user@cloud.example.com',
          expected: WebDavServerUrlError.embeddedUserInfo,
        ),
        (
          input: '@cloud.example.com',
          expected: WebDavServerUrlError.embeddedUserInfo,
        ),
        (
          input: 'ftp://cloud.example.com',
          expected: WebDavServerUrlError.invalid,
        ),
        (input: 'file:///etc/passwd', expected: WebDavServerUrlError.invalid),
        (input: 'file:/etc/passwd', expected: WebDavServerUrlError.invalid),
        (
          input: 'http:/cloud.example.com',
          expected: WebDavServerUrlError.invalid,
        ),
        (
          input: 'https:/cloud.example.com',
          expected: WebDavServerUrlError.invalid,
        ),
        (
          input: 'http:cloud.example.com',
          expected: WebDavServerUrlError.invalid,
        ),
        (input: 'javascript:alert(1)', expected: WebDavServerUrlError.invalid),
        (input: '://missing-scheme', expected: WebDavServerUrlError.invalid),
        (input: 'https://', expected: WebDavServerUrlError.invalid),
        (
          input: 'http:///dav/tasks.tdf',
          expected: WebDavServerUrlError.invalid,
        ),
        (input: '/dav/tasks.tdf', expected: WebDavServerUrlError.invalid),
        (input: '//cloud.example.com', expected: WebDavServerUrlError.invalid),
        (input: 'cloud.example.com:', expected: WebDavServerUrlError.invalid),
        (
          input: 'cloud.example.com:/dav',
          expected: WebDavServerUrlError.invalid,
        ),
        (
          input: 'https://cloud.example.com:0',
          expected: WebDavServerUrlError.invalid,
        ),
        (
          input: 'https://cloud.example.com:65536',
          expected: WebDavServerUrlError.invalid,
        ),
        (
          input: 'cloud.example.com?token=1',
          expected: WebDavServerUrlError.invalid,
        ),
        (
          input: 'cloud.example.com#section',
          expected: WebDavServerUrlError.invalid,
        ),
        (
          input: 'cloud.example.com/../secret',
          expected: WebDavServerUrlError.invalid,
        ),
        (
          input: 'cloud.example.com/./dav',
          expected: WebDavServerUrlError.invalid,
        ),
        (
          input: 'https://cloud.example.com/../secret',
          expected: WebDavServerUrlError.invalid,
        ),
        (
          input: 'https://cloud.example.com/./dav',
          expected: WebDavServerUrlError.invalid,
        ),
        (
          input: r'cloud.example.com\dav',
          expected: WebDavServerUrlError.invalid,
        ),
        (
          input: r'https://cloud.example.com\dav',
          expected: WebDavServerUrlError.invalid,
        ),
        (input: 'starknet .one', expected: WebDavServerUrlError.invalid),
        (input: '..', expected: WebDavServerUrlError.invalid),
        (input: '.', expected: WebDavServerUrlError.invalid),
        (input: 'starknet.one\n', expected: WebDavServerUrlError.invalid),
        (input: 'starknet.one/\x00', expected: WebDavServerUrlError.invalid),
      ];
      for (final testCase in invalidCases) {
        expect(
          WebDavConfig.validateServerUrl(testCase.input),
          equals(testCase.expected),
          reason: 'Unexpected validation error for "${testCase.input}"',
        );
        final config = WebDavConfig(
          serverUrl: testCase.input,
          username: 'alice',
          filePath: 'test.tdf',
        );
        expect(
          config.resolveEndpointUri(),
          isNull,
          reason:
              'Invalid serverUrl "${testCase.input}" must resolve null endpoint',
        );
      }
    });
  });

  group('TDF 0.7.0 Primitives, Bounds, TdfLabel Links, TaskHistoryEntry & TaskItem Ownership', () {
    test('exposes structural resource bounds for ordinary blocks, label links, and task history', () {
      expect(maxTdfStmtsPerBlock, equals(1024));
      expect(maxTdfLinksPerLabel, equals(20));
      expect(maxTdfHistoryPerTask, equals(500));
    });

    test('supports TdfLabel.links unmodifiable copyWith, equality, hashCode, and canonicalDirectChildStatementCount', () {
      const baseLabel = TdfLabel(id: 'lblWork001', name: 'Work');
      expect(baseLabel.links, isEmpty);
      expect(baseLabel.canonicalDirectChildStatementCount, equals(1));

      final mutableLinks = <TaskLink>[
        const TaskLink(title: 'Portal', uri: 'https://example.com/portal'),
        const TaskLink(title: 'Docs', uri: 'https://example.com/docs'),
      ];
      final updated = baseLabel.copyWith(
        color: '#112233',
        note: 'Engineering context',
        isScoped: true,
        modifiedAt: DateTime.utc(2026, 11, 1, 10),
        links: mutableLinks,
        conditions: <TaskCondition>[
          DayTaskCondition.fromWeekdays(const <int>[1, 2, 3, 4, 5]),
        ],
      );
      mutableLinks.clear();
      expect(
        updated.links.length,
        equals(2),
        reason: 'TdfLabel.copyWith must wrap links in an unmodifiable list',
      );
      expect(
        () => updated.links.add(
          const TaskLink(title: 'Extra', uri: 'https://example.com/extra'),
        ),
        throwsUnsupportedError,
      );
      expect(
        updated.canonicalDirectChildStatementCount,
        equals(7),
        reason: 'name (1) + color (1) + note (1) + modified (1) + 2 links (2) + condition (1) = 7 direct child statements (scoped is a header flag)',
      );

      final identicalCopy = updated.copyWith();
      expect(identicalCopy, equals(updated));
      expect(identicalCopy.hashCode, equals(updated.hashCode));
      expect(
        updated.copyWith(links: const <TaskLink>[]),
        isNot(equals(updated)),
      );
    });

    test('sorts and deduplicates TaskHistoryEntry by UTC epoch and unsigned UTF-8 byte order', () {
      final t1 = DateTime.utc(2026, 11, 1, 9, 0, 5, 999);
      final t2 = DateTime.utc(2026, 11, 1, 9, 0, 6);
      // U+FFFD encodes to UTF-8 [0xEF, 0xBF, 0xBD]; U+1F600 encodes to [0xF0, 0x9F, 0x98, 0x80].
      // In UTF-16 code units, U+1F600 starts with 0xD83D < 0xFFFD, whereas unsigned UTF-8 sorts 0xEF < 0xF0!
      const bmpReplacement = '\uFFFD';
      final astralChar = String.fromCharCode(0x1F600);

      final entryAstral = TaskHistoryEntry(timestampUtc: t1, text: astralChar);
      final entryBmp = TaskHistoryEntry(timestampUtc: t1, text: bmpReplacement);
      final entryDuplicate = TaskHistoryEntry(
        timestampUtc: DateTime.utc(2026, 11, 1, 9, 0, 5),
        text: bmpReplacement,
      );
      final entryLater = TaskHistoryEntry(timestampUtc: t2, text: 'Alpha');

      expect(
        entryAstral.timestampUtc,
        equals(DateTime.utc(2026, 11, 1, 9, 0, 5)),
        reason: 'TaskHistoryEntry must truncate sub-second precision to UTC seconds',
      );
      expect(
        TaskHistoryEntry.compareCanonical(entryBmp, entryAstral),
        lessThan(0),
        reason: 'Unsigned UTF-8 byte comparison must order 0xEF (U+FFFD) before 0xF0 (U+1F600)',
      );
      expect(entryBmp, equals(entryDuplicate));
      expect(entryBmp.hashCode, equals(entryDuplicate.hashCode));
      expect(
        entryLater.toString(),
        isNot(contains('Alpha')),
        reason:
            'TaskHistoryEntry.toString must redact user-authored history text',
      );

      final normalized = TaskHistoryEntry.normalizeList(<TaskHistoryEntry>[
        entryLater,
        entryAstral,
        entryBmp,
        entryDuplicate,
      ]);
      expect(
        normalized,
        equals(<TaskHistoryEntry>[entryBmp, entryAstral, entryLater]),
      );
      expect(() => normalized.add(entryLater), throwsUnsupportedError);
      expect(
        TaskHistoryEntry.normalizeList(const <TaskHistoryEntry>[]),
        isEmpty,
      );
    });

    test('computes TDF 0.7.0 TaskRepeatRule.nextScheduleAnchoredOccurrence using leadDays and clamps out-of-range dates', () {
      const ruleNoLead = TaskRepeatRule(count: 1, unit: RepeatUnit.weeks);
      expect(ruleNoLead.leadDays, equals(0));
      expect(ruleNoLead.toTdfDirectiveArgs(), equals('1 weeks'));

      const ruleWithLeadAndClock = TaskRepeatRule(
        count: 1,
        unit: RepeatUnit.months,
        clock: TdfRepeatClock(hour: 9, minute: 30),
        leadDays: 5,
      );
      expect(
        ruleWithLeadAndClock.toTdfDirectiveArgs(),
        equals('1 months 09:30 lead 5 days'),
      );
      expect(ruleWithLeadAndClock.copyWith(leadDays: 0).leadDays, equals(0));
      expect(
        ruleWithLeadAndClock.copyWith(leadDays: 2),
        isNot(equals(ruleWithLeadAndClock)),
      );

      // Month-end clamping: 2026-01-31 18:00 CET -> 2026-02-28 18:00 CET, minus 5 lead days -> 2026-02-23 09:30 CET.
      const berlin = TdfTimeZoneContext.europeBerlin;
      final oldDueUtc = berlin.resolveLocalToUtc(2026, 1, 31, 18, 0, 0);
      final completedUtc = berlin.resolveLocalToUtc(2026, 1, 30, 12, 0, 0);
      final febOccurrence = ruleWithLeadAndClock.computeNextMode2Schedule(
        completedAtUtc: completedUtc,
        oldDueUtc: oldDueUtc,
        timeZone: berlin,
      );
      expect(febOccurrence.stepsK, equals(1));
      expect(
        febOccurrence.newDueUtc,
        equals(berlin.resolveLocalToUtc(2026, 2, 28, 18, 0, 0)),
      );
      expect(
        febOccurrence.newAnchor,
        equals(TdfLocalDateTime(2026, 1, 31, 18)),
        reason: 'Clamped Feb 28 must preserve derived Jan 31 18:00:00 anchor',
      );
      expect(
        febOccurrence.newSuspendedUtc,
        equals(berlin.resolveLocalToUtc(2026, 2, 23, 9, 30, 0)),
      );

      // Clamping when leadDays == 0 and repeat clock (20:00) is later on the same day than due (10:00):
      const lateClockRule = TaskRepeatRule(
        count: 1,
        unit: RepeatUnit.days,
        clock: TdfRepeatClock(hour: 20),
      );
      final morningDue = DateTime.utc(2026, 11, 1, 10);
      final clamped = lateClockRule.computeNextMode2Schedule(
        completedAtUtc: DateTime.utc(2026, 11, 1, 8),
        oldDueUtc: morningDue,
        timeZone: TdfTimeZoneContext.utc,
      );
      expect(clamped.newDueUtc, equals(DateTime.utc(2026, 11, 2, 10)));
      expect(
        clamped.newSuspendedUtc,
        equals(DateTime.utc(2026, 11, 2, 10)),
        reason: 'candidateSuspended > newDue must clamp newSuspendedUtc to newDueUtc',
      );

      // Subtracting leadDays before year 0001 must throw TdfException(invalidTimestamp):
      const hugeLeadRule = TaskRepeatRule(
        count: 1,
        unit: RepeatUnit.days,
        leadDays: 10,
      );
      expect(
        () => hugeLeadRule.computeNextMode2Schedule(
          completedAtUtc: DateTime.utc(1),
          oldDueUtc: DateTime.utc(1, 1, 2, 12),
          timeZone: TdfTimeZoneContext.utc,
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.invalidTimestamp,
          ),
        ),
      );
    });

    test('enforces TaskItem ownership normalization, dueLeadWindow checks, toCompleted rules, and canonicalDirectChildStatementCount', () {
      final now = DateTime.utc(2026, 11, 1, 12);

      // Orphaned isDuePassive, dueNote, and suspendedNote are normalized away on construction:
      final orphanNormalized = TaskItem(
        id: 'tOrphan001',
        title: 'Orphan Check',
        createdAt: now,
        isDuePassive: true,
        dueNote: 'Should drop without dueAt',
        suspendedNote: 'Should drop without suspended',
      );
      expect(orphanNormalized.isDuePassive, isFalse);
      expect(orphanNormalized.dueNote, isNull);
      expect(orphanNormalized.suspendedNote, isNull);

      final scheduled = TaskItem(
        id: 'tSched0001',
        title: 'Scheduled Task',
        createdAt: now,
        suspendedAt: now.add(const Duration(hours: 2)),
        suspendedNote: 'Waiting on deploy window',
        dueAt: now.add(const Duration(hours: 24)),
        dueNote: 'Contract SLA',
        origin: const TaskOrigin(namespace: 'jira', externalKey: 'OPS-1'),
        history: <TaskHistoryEntry>[
          TaskHistoryEntry(timestampUtc: now, text: 'Created ticket'),
        ],
      );
      expect(scheduled.hasActiveSuspendedAt(now), isTrue);
      expect(
        scheduled.hasActiveSuspendedAt(now.add(const Duration(hours: 2))),
        isFalse,
        reason: 'suspendedAt == now is expired (active requires strict > now)',
      );
      expect(
        scheduled.isWithinDueLeadWindow(now, const Duration(hours: 24)),
        isTrue,
        reason: 'Exact +24h boundary is inclusive (<= now + dueLeadWindow)',
      );
      expect(
        scheduled.isWithinDueLeadWindow(
          now,
          const Duration(hours: 23, minutes: 59, seconds: 59),
        ),
        isFalse,
      );
      expect(scheduled.isWithinDueLeadWindow(now, null), isFalse);

      final passiveCopy = scheduled.copyWith(isDuePassive: true);
      expect(
        passiveCopy.isWithinDueLeadWindow(now, const Duration(hours: 48)),
        isFalse,
        reason: 'isDuePassive suppresses dueLeadWindow urgency',
      );

      final clearedSchedule = passiveCopy.copyWith(
        clearSuspendedAt: true,
        clearDueAt: true,
      );
      expect(clearedSchedule.suspendedNote, isNull);
      expect(clearedSchedule.dueNote, isNull);
      expect(clearedSchedule.isDuePassive, isFalse);

      final completed = passiveCopy
          .copyWith(
            isPriority: true,
            dependencies: const <TdfTaskDependency>[
              TdfTaskDependency(taskId: 'dep0000001'),
            ],
          )
          .toCompleted(now.add(const Duration(hours: 3)));
      expect(completed.isCompleted, isTrue);
      expect(completed.isPriority, isFalse);
      expect(completed.isSuspendedForever, isFalse);
      expect(completed.suspendedAt, isNull);
      expect(completed.suspendedNote, isNull);
      expect(completed.dependencies, isEmpty);
      expect(completed.dueAt, equals(scheduled.dueAt));
      expect(completed.isDuePassive, isTrue);
      expect(completed.dueNote, equals('Contract SLA'));
      expect(completed.origin, equals(scheduled.origin));
      expect(completed.history, equals(scheduled.history));

      // Full-capacity canonical open/completed task statement count:
      final fullHistory = <TaskHistoryEntry>[
        for (var i = 0; i < maxTdfHistoryPerTask; i++)
          TaskHistoryEntry(
            timestampUtc: now.add(Duration(seconds: i)),
            text: 'Event $i',
          ),
      ];
      final fullLinks = <TaskLink>[
        for (var i = 0; i < TaskLink.maxLinksPerTask; i++)
          TaskLink(title: 'Link $i', uri: 'https://example.com/$i'),
      ];
      final fullCapacityTask = TaskItem(
        id: 'tMaxCap001',
        title: 'Full Capacity',
        note: 'Detailed body',
        createdAt: now,
        isCompleted: true,
        completedAt: now,
        modifiedAt: now,
        completions: 3,
        repeatRule: const TaskRepeatRule(
          count: 1,
          unit: RepeatUnit.days,
          leadDays: 1,
        ),
        labelIds: const <String>['lblWork001'],
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'dep0000001'),
        ],
        suspendedAt: now.add(const Duration(days: 1)),
        suspendedNote: 'Suspended note',
        dueAt: now.add(const Duration(days: 2)),
        isDuePassive: true,
        dueNote: 'Due note',
        origin: const TaskOrigin(namespace: 'ns', externalKey: 'k'),
        links: fullLinks,
        history: fullHistory,
        conditions: const <TaskCondition>[GlobalResetTaskCondition()],
        subtasks: const <SubtaskItem>[SubtaskItem(title: 'Step 1')],
      );
      expect(
        fullCapacityTask.canonicalDirectChildStatementCount,
        equals(534),
        reason: '12 scalar directives + 20 links + 500 history + 1 condition + 1 subtasks = 534 <= 1024',
      );
      expect(
        fullCapacityTask.canonicalDirectChildStatementCount <=
            maxTdfStmtsPerBlock,
        isTrue,
      );
    });

    test('exposes TdfLabel.maxLinksPerLabel and enforces Unicode scalar and control-character parity in TaskLink.tryParse', () {
      expect(
        TdfLabel.maxLinksPerLabel,
        equals(20),
        reason:
            'TdfLabel.maxLinksPerLabel must expose maxTdfLinksPerLabel (20)',
      );

      final astralTitle500 = '\u{10400}' * 500;
      expect(
        astralTitle500.length,
        equals(1000),
        reason: '500 supplementary-plane scalars occupy 1000 UTF-16 code units',
      );
      final parsedAstral500 = TaskLink.tryParse(
        rawTitle: '  $astralTitle500  ',
        rawUri: '  https://example.com/runbook?q=1&b=2#sec-3  ',
      );
      expect(
        parsedAstral500,
        equals(
          TaskLink(
            title: astralTitle500,
            uri: 'https://example.com/runbook?q=1&b=2#sec-3',
          ),
        ),
        reason: 'TaskLink.tryParse must accept 500 Unicode scalar values and trim ASCII spaces',
      );

      expect(
        TaskLink.tryParse(
          rawTitle: '\u{10400}' * 501,
          rawUri: 'https://example.com',
        ),
        isNull,
        reason: '501 astral Unicode scalar values must be rejected',
      );
      expect(
        TaskLink.tryParse(rawTitle: 'a' * 501, rawUri: 'https://example.com'),
        isNull,
        reason: '501 ASCII characters must be rejected',
      );

      const uriPrefix = 'https://example.com/';
      final uri2048 =
          '$uriPrefix${'\u{1F600}' * (TaskLink.maxUriLength - uriPrefix.length)}';
      expect(
        TaskLink.tryParse(rawTitle: 'Docs', rawUri: uri2048),
        equals(TaskLink(title: 'Docs', uri: uri2048)),
        reason: '2048 Unicode scalar values in URI must succeed',
      );
      expect(
        TaskLink.tryParse(rawTitle: 'Docs', rawUri: '$uri2048\u{1F600}'),
        isNull,
        reason: '2049 Unicode scalar values in URI must be rejected',
      );

      final controlSamples = <String>[
        '\nDocs',
        'Docs\n',
        'Do\ncs',
        '\rDocs',
        'Docs\r',
        '\tDocs',
        'Docs\t',
        'Do\tcs',
        '\x00Docs',
        'Docs\x00',
        'Do\x00cs',
        'Docs\x7F',
        'Do\x1Fcs',
      ];
      for (final badTitle in controlSamples) {
        expect(
          TaskLink.tryParse(rawTitle: badTitle, rawUri: 'https://example.com'),
          isNull,
          reason:
              'Control character in title (${badTitle.codeUnits}) must fail before trim',
        );
      }

      final badUriControlSamples = <String>[
        '\nhttps://example.com',
        'https://example.com\n',
        '\rhttps://example.com',
        'https://example.com\t',
        '\x00https://example.com',
        'https://example.com\x00',
        'https://example.com/a\x7Fb',
      ];
      for (final badUri in badUriControlSamples) {
        expect(
          TaskLink.tryParse(rawTitle: 'Docs', rawUri: badUri),
          isNull,
          reason:
              'Control character in URI (${badUri.codeUnits}) must fail before trim',
        );
      }

      final unpairedHigh = String.fromCharCodes(const <int>[
        0x41,
        0xD800,
        0x42,
      ]);
      final unpairedLow = String.fromCharCodes(const <int>[0x41, 0xDC00, 0x42]);
      expect(
        TaskLink.tryParse(
          rawTitle: unpairedHigh,
          rawUri: 'https://example.com',
        ),
        isNull,
        reason: 'Unpaired high surrogate in title must be rejected',
      );
      expect(
        TaskLink.tryParse(rawTitle: unpairedLow, rawUri: 'https://example.com'),
        isNull,
        reason: 'Unpaired low surrogate in title must be rejected',
      );
      expect(
        TaskLink.tryParse(
          rawTitle: 'Docs',
          rawUri: 'https://example.com/$unpairedHigh',
        ),
        isNull,
        reason: 'Unpaired surrogate in URI must be rejected',
      );

      for (final emptyTitle in const <String>['', ' ', '   ']) {
        expect(
          TaskLink.tryParse(
            rawTitle: emptyTitle,
            rawUri: 'https://example.com',
          ),
          isNull,
          reason: 'Empty or space-only title must be rejected',
        );
      }

      for (final forbiddenOrMalformedUri in const <String>[
        '',
        '   ',
        'example.com',
        '/local/path',
        '../secret',
        ':noscheme',
        'javascript:alert(1)',
        'JaVaScRiPt:void(0)',
        'vbscript:msgbox(1)',
        'VBSCRIPT:run',
        'data:text/html,<h1>x</h1>',
        'DaTa:text/plain,abc',
      ]) {
        expect(
          TaskLink.tryParse(rawTitle: 'Docs', rawUri: forbiddenOrMalformedUri),
          isNull,
          reason:
              'Invalid or forbidden URI "$forbiddenOrMalformedUri" must be rejected',
        );
      }

      for (final validUri in const <String>[
        'mailto:ops@example.com?subject=Runbook',
        'file:///C:/Project Docs/spec v1.pdf',
        'file:///home/user/docs/../readme.md#overview',
      ]) {
        expect(
          TaskLink.tryParse(rawTitle: 'Ref', rawUri: validUri),
          equals(TaskLink(title: 'Ref', uri: validUri)),
          reason: 'Permitted URI "$validUri" must succeed',
        );
      }
    });
  });

  group('TDF 0.8.0 Bounds, TdfLocalDateTime, TimeZone Engine & Mode 2 Schedule Anchors', () {
    test('exposes all 22 TDF 0.8.0 Section 6.2 bounds, defaultDueLeadSeconds, tdfSupportedVersion, and sync enums', () {
      expect(tdfSupportedVersion, equals('0.8.0'));
      expect(defaultDueLeadSeconds, equals(86400));
      expect(maxTdfFileBytes, equals(1048576));
      expect(maxTdfLineCount, equals(16384));
      expect(maxTdfNestingDepth, equals(2));
      expect(maxTdfBlocksPerDoc, equals(4096));
      expect(maxTdfLocations, equals(200));
      expect(maxTdfStmtsPerBlock, equals(1024));
      expect(maxTdfConditionRulesPerEntity, equals(512));
      expect(maxTdfLocationRefsPerEntity, equals(63));
      expect(maxTdfQueueEntries, equals(4096));
      expect(maxTdfDeletedRecords, equals(4096));
      expect(maxTdfSyncGeneration, equals(9007199254740991));
      expect(maxTdfCompletions, equals(9007199254740991));
      expect(maxTdfArgsPerStmt, equals(64));
      expect(maxTdfTextLength, equals(500));
      expect(maxTdfNoteLength, equals(2000));
      expect(maxTdfUriLength, equals(2048));
      expect(maxTdfLinksPerTask, equals(20));
      expect(maxTdfLinksPerLabel, equals(20));
      expect(maxTdfHistoryPerTask, equals(500));
      expect(maxTdfRepeatCount, equals(3650));
      expect(maxTdfLocationRadius, equals(100000));
      expect(maxTdfNumberLength, equals(24));

      expect(
        TdfCleanupMode.values,
        equals(const <TdfCleanupMode>[
          TdfCleanupMode.finalStage,
          TdfCleanupMode.deferred,
        ]),
      );
      expect(
        TdfRecoveryResolution.values,
        equals(const <TdfRecoveryResolution>[
          TdfRecoveryResolution.discard,
          TdfRecoveryResolution.recoverAsNew,
        ]),
      );

      final decision = TdfBoundDeletionDecision(
        resolution: TdfDeletionResolution.undelete,
        expectedLiveModifiedAt: DateTime.utc(2026, 11, 16, 9),
        expectedDeletionAt: DateTime.utc(2026, 11, 16, 10),
        expectedLivePayloadSignature: 'sig-1',
      );
      expect(
        decision,
        equals(
          TdfBoundDeletionDecision(
            resolution: TdfDeletionResolution.undelete,
            expectedLiveModifiedAt: DateTime.utc(2026, 11, 16, 9),
            expectedDeletionAt: DateTime.utc(2026, 11, 16, 10),
            expectedLivePayloadSignature: 'sig-1',
          ),
        ),
      );
      expect(
        decision,
        isNot(
          equals(
            TdfBoundDeletionDecision(
              resolution: TdfDeletionResolution.undelete,
              expectedLiveModifiedAt: DateTime.utc(2026, 11, 16, 9),
              expectedDeletionAt: DateTime.utc(2026, 11, 16, 10),
              expectedLivePayloadSignature: 'sig-2',
            ),
          ),
        ),
      );
    });

    test('validates, parses, formats, and compares TdfLocalDateTime across 0001..9999', () {
      final minVal = TdfLocalDateTime(1, 1, 1);
      final maxVal = TdfLocalDateTime(9999, 12, 31, 23, 59, 59);
      expect(minVal.formatExplicitSeconds(), equals('0001-01-01 00:00:00'));
      expect(minVal.formatCompact(), equals('0001-01-01 00:00'));
      expect(maxVal.formatExplicitSeconds(), equals('9999-12-31 23:59:59'));
      expect(maxVal.formatCompact(), equals('9999-12-31 23:59:59'));
      expect(minVal.compareTo(maxVal), lessThan(0));
      expect(maxVal.compareTo(minVal), greaterThan(0));
      expect(minVal.compareTo(TdfLocalDateTime(1, 1, 1)), equals(0));
      expect(
        TdfLocalDateTime.fromWallClock(DateTime.utc(2026, 2, 28, 18, 0, 5)),
        equals(TdfLocalDateTime(2026, 2, 28, 18, 0, 5)),
      );
      expect(
        TdfLocalDateTime.tryParse('2000-02-29', '08:30'),
        equals(TdfLocalDateTime(2000, 2, 29, 8, 30)),
      );
      expect(
        TdfLocalDateTime.tryParseInput('2026-01-31 18:00:05'),
        equals(TdfLocalDateTime(2026, 1, 31, 18, 0, 5)),
      );
      expect(TdfLocalDateTime.tryParse('1900-02-29'), isNull);
      expect(TdfLocalDateTime.tryParse('0000-01-01'), isNull);
      expect(TdfLocalDateTime.tryParseInput('2026-01-31 24:00'), isNull);
      expect(() => TdfLocalDateTime(0, 1, 1), throwsFormatException);
      expect(() => TdfLocalDateTime(10000, 1, 1), throwsFormatException);
      expect(() => TdfLocalDateTime(2026, 2, 29), throwsFormatException);
      expect(
        () => TdfLocalDateTime(2026, 1, 1, 23, 59, 60),
        throwsFormatException,
      );
    });

    test('counts explicit epoch modifiedAt on TdfLabel.canonicalDirectChildStatementCount', () {
      final epochStamped = TdfLabel(
        id: '4x9p2mOkD2',
        name: 'Home',
        modifiedAt: DateTime.utc(1970),
      );
      const unstamped = TdfLabel(id: '4x9p2mOkD2', name: 'Home');
      expect(
        epochStamped.canonicalDirectChildStatementCount,
        equals(2),
        reason: 'Explicit modified 1970-01-01 00:00 must be emitted and counted in 0.8.0',
      );
      expect(unstamped.canonicalDirectChildStatementCount, equals(1));
    });

    test('resolves TdfTimeZoneContext.named(America/New_York), systemLocal() pre-1601/9999 safety, and customObserver negative/sub-hour DST gaps and folds', () {
      final ny = TdfTimeZoneContext.named('America/New_York');
      expect(ny.isAvailable, isTrue);
      // 2026-03-08 02:30 local falls in EST->EDT spring gap (02:00 -> 03:00); pre-gap EST (-05:00) -> 07:30:00 UTC.
      expect(
        ny.resolveLocalToUtc(2026, 3, 8, 2, 30, 0),
        equals(DateTime.utc(2026, 3, 8, 7, 30)),
      );
      expect(
        ny.toLocalWallClock(DateTime.utc(2026, 3, 8, 7, 30)),
        equals(DateTime.utc(2026, 3, 8, 3, 30)),
      );
      // 2026-11-01 01:30 local falls in EDT->EST autumn fold (01:00..01:59 repeats); first occurrence is EDT (-04:00) -> 05:30:00 UTC.
      expect(
        ny.resolveLocalToUtc(2026, 11, 1, 1, 30, 0),
        equals(DateTime.utc(2026, 11, 1, 5, 30)),
      );
      // Second occurrence 06:30:00 UTC still formats to 01:30:00 local EST:
      expect(
        ny.toLocalWallClock(DateTime.utc(2026, 11, 1, 6, 30)),
        equals(DateTime.utc(2026, 11, 1, 1, 30)),
      );
      // Boundary overflow: 9999-12-31 23:30 in EST (-05:00) -> 10000-01-01 04:30 UTC -> InvalidTimestamp:
      expect(
        () => ny.resolveLocalToUtc(9999, 12, 31, 23, 30, 0),
        throwsFormatException,
      );

      // Synthetic negative-DST observer (Ireland-style: standard IST = +01:00 in summer, negative winter DST = +00:00;
      // autumn fold in October +3600 -> 0; spring forward jump in March 0 -> +3600 at 01:00 UTC creating gap 01:00..01:59 local):
      final gapTransitionUtcSec =
          DateTime.utc(2026, 3, 29, 1).millisecondsSinceEpoch ~/ 1000;
      final foldTransitionUtcSec =
          DateTime.utc(2026, 10, 25, 1).millisecondsSinceEpoch ~/ 1000;
      var minObservedEpochSec = 1 << 60;
      final negativeDstZone = TdfTimeZoneContext.customObserver(
        'Test/NegativeDST',
        (int utcEpochSeconds) {
          if (utcEpochSeconds < minObservedEpochSec) {
            minObservedEpochSec = utcEpochSeconds;
          }
          if (utcEpochSeconds >= gapTransitionUtcSec &&
              utcEpochSeconds < foldTransitionUtcSec) {
            return 3600;
          }
          return 0;
        },
      );
      // Gap at 2026-03-29 01:30 local -> pre-gap offset 0 -> 01:30:00 UTC (02:30 local):
      expect(
        negativeDstZone.resolveLocalToUtc(2026, 3, 29, 1, 30, 0),
        equals(DateTime.utc(2026, 3, 29, 1, 30)),
      );
      // Fold at 2026-10-25 01:30 local -> occurs at 00:30 UTC (+3600) and 01:30 UTC (0); earliest is 00:30 UTC:
      expect(
        negativeDstZone.resolveLocalToUtc(2026, 10, 25, 1, 30, 0),
        equals(DateTime.utc(2026, 10, 25, 0, 30)),
      );

      // Sub-hour (30-minute) DST observer (Lord Howe style: +10:30 = 37800s -> +11:00 = 39600s at 2026-10-04 15:30 UTC, gap 02:00..02:29 local):
      final subHourJumpSec =
          DateTime.utc(2026, 10, 4, 15, 30).millisecondsSinceEpoch ~/ 1000;
      final subHourZone = TdfTimeZoneContext.customObserver(
        'Test/LordHowe',
        (int s) => s >= subHourJumpSec ? 39600 : 37800,
      );
      expect(
        subHourZone.resolveLocalToUtc(2026, 10, 5, 2, 15, 0),
        equals(DateTime.utc(2026, 10, 4, 15, 45)),
        reason:
            '30-minute gap must use pre-gap +10:30 offset via binary search',
      );

      // systemLocal() pre-1601 Win32 guard & 0001..9999 safety:
      const sysZone = TdfTimeZoneContext.systemLocal();
      expect(sysZone.isAvailable, isTrue);
      // Must not crash on year 0002 or year 9998 in any host time zone:
      final y2Utc = sysZone.resolveLocalToUtc(2, 6, 15, 12, 0, 0);
      expect(
        sysZone.toLocalWallClock(y2Utc),
        equals(DateTime.utc(2, 6, 15, 12)),
      );
      final y9998Utc = sysZone.resolveLocalToUtc(9998, 6, 15, 12, 0, 0);
      expect(
        sysZone.toLocalWallClock(y9998Utc),
        equals(DateTime.utc(9998, 6, 15, 12)),
      );

      const autoConfig = WebDavConfig();
      expect(autoConfig.resolveTimeZoneContext(), equals(sysZone));
      const manualConfig = WebDavConfig(
        timeZoneMode: AppTimeZoneMode.manual,
        manualTimeZoneOffsetMinutes: 120,
      );
      expect(
        manualConfig.localWallClockToUtc(DateTime.utc(2026, 11, 16, 12)),
        equals(DateTime.utc(2026, 11, 16, 10)),
      );
      expect(
        manualConfig.toLocalWallClock(DateTime.utc(2026, 11, 16, 10)),
        equals(DateTime.utc(2026, 11, 16, 12)),
      );
    });

    test('enforces TaskItem.dueAnchor ownership and TDF-CAL-003 (Y_cur, M_cur) Mode 2 recurrence progression', () {
      // Ownership invariant: dueAnchor dropped when dueAt is null or cleared:
      final orphanAnchor = TaskItem(
        id: '8jKaCdOkD2',
        title: 'Orphan anchor',
        dueAnchor: TdfLocalDateTime(2026, 1, 31, 18),
      );
      expect(orphanAnchor.dueAnchor, isNull);

      final withAnchor = TaskItem(
        id: '8jKaCdOkD2',
        title: 'Anchored',
        dueAt: DateTime.utc(2026, 2, 28, 17),
        dueAnchor: TdfLocalDateTime(2026, 1, 31, 18),
      );
      expect(withAnchor.dueAnchor, equals(TdfLocalDateTime(2026, 1, 31, 18)));
      expect(withAnchor.copyWith(clearDueAt: true).dueAnchor, isNull);
      expect(
        withAnchor.copyWith(clearDueAnchor: true).dueAt,
        equals(DateTime.utc(2026, 2, 28, 17)),
      );
      expect(withAnchor.copyWith(clearDueAnchor: true).dueAnchor, isNull);
      expect(
        withAnchor.toCompleted(DateTime.utc(2026, 2, 28, 12)).dueAnchor,
        equals(TdfLocalDateTime(2026, 1, 31, 18)),
      );
      expect(withAnchor.toActive(clearDueAt: true).dueAnchor, isNull);

      // TDF-CAL-003 Vector: Month-end anchor preservation (k = 1 + 1 vs k = 2 and repeat interval edit on clamped month):
      const berlin = TdfTimeZoneContext.europeBerlin;
      const monthlyRule = TaskRepeatRule(
        count: 1,
        unit: RepeatUnit.months,
        clock: TdfRepeatClock(hour: 8),
        leadDays: 2,
      );
      final jan31DueUtc = DateTime.utc(2026, 1, 31, 17);
      final jan31Anchor = TdfLocalDateTime(2026, 1, 31, 18);

      // Step 1 (k = 1 on Jan 31): clamps to Feb 28 17:00 UTC, preserves anchor 2026-01-31 18:00:00:
      final step1 = monthlyRule.computeNextMode2Schedule(
        completedAtUtc: DateTime.utc(2026, 1, 31, 10),
        oldDueUtc: jan31DueUtc,
        oldAnchor: jan31Anchor,
        timeZone: berlin,
      );
      expect(step1.newDueUtc, equals(DateTime.utc(2026, 2, 28, 17)));
      expect(step1.newAnchor, equals(jan31Anchor));
      expect(step1.newSuspendedUtc, equals(DateTime.utc(2026, 2, 26, 7)));

      // Step 2 (k = 1 on Feb 28): advances (Y_cur, M_cur) = (2026, 2) by 1 month with D_a = 31 -> Mar 31 16:00 UTC (18:00 CEST):
      final step2 = monthlyRule.computeNextMode2Schedule(
        completedAtUtc: DateTime.utc(2026, 2, 28, 10),
        oldDueUtc: step1.newDueUtc,
        oldAnchor: step1.newAnchor,
        timeZone: berlin,
      );
      expect(step2.newDueUtc, equals(DateTime.utc(2026, 3, 31, 16)));
      expect(step2.newAnchor, equals(TdfLocalDateTime(2026, 3, 31, 18)));
      expect(step2.newSuspendedUtc, equals(DateTime.utc(2026, 3, 29, 6)));

      // Direct k = 2 jump when Jan 31 is completed late on 2026-03-10:
      final directK2 = monthlyRule.computeNextMode2Schedule(
        completedAtUtc: DateTime.utc(2026, 3, 10, 10),
        oldDueUtc: jan31DueUtc,
        oldAnchor: jan31Anchor,
        timeZone: berlin,
      );
      expect(directK2.newDueUtc, equals(step2.newDueUtc));
      expect(directK2.newAnchor, equals(step2.newAnchor));
      expect(directK2.newSuspendedUtc, equals(step2.newSuspendedUtc));

      // Editing repeat 1 months -> repeat 2 months on the clamped Feb 28 state:
      const biMonthlyRule = TaskRepeatRule(
        count: 2,
        unit: RepeatUnit.months,
        clock: TdfRepeatClock(hour: 8),
        leadDays: 2,
      );
      final aprStep = biMonthlyRule.computeNextMode2Schedule(
        completedAtUtc: DateTime.utc(2026, 2, 28, 10),
        oldDueUtc: step1.newDueUtc,
        oldAnchor: step1.newAnchor,
        timeZone: berlin,
      );
      expect(
        aprStep.newDueUtc,
        equals(DateTime.utc(2026, 4, 30, 16)),
        reason: 'Advancing (Y_cur, M_cur) = (2026, 2) by 2 months clamps D_a=31 to Apr 30 18:00 CEST',
      );
      expect(
        aprStep.newAnchor,
        equals(jan31Anchor),
        reason: 'Clamped Apr 30 (30 < 31) must still retain anchor 2026-01-31 18:00:00',
      );
      final junStep = biMonthlyRule.computeNextMode2Schedule(
        completedAtUtc: DateTime.utc(2026, 4, 30, 10),
        oldDueUtc: aprStep.newDueUtc,
        oldAnchor: aprStep.newAnchor,
        timeZone: berlin,
      );
      expect(junStep.newDueUtc, equals(DateTime.utc(2026, 6, 30, 16)));
      expect(junStep.newAnchor, equals(jan31Anchor));
      final augStep = biMonthlyRule.computeNextMode2Schedule(
        completedAtUtc: DateTime.utc(2026, 6, 30, 10),
        oldDueUtc: junStep.newDueUtc,
        oldAnchor: junStep.newAnchor,
        timeZone: berlin,
      );
      expect(augStep.newDueUtc, equals(DateTime.utc(2026, 8, 31, 16)));
      expect(augStep.newAnchor, equals(TdfLocalDateTime(2026, 8, 31, 18)));

      // Forward DST gap deadline-clock preservation (2026-03-28 02:30 -> Mar 29 03:30 CEST -> Mar 30 02:30 CEST):
      const dailyRule = TaskRepeatRule(count: 1, unit: RepeatUnit.days);
      final gapStep1 = dailyRule.computeNextMode2Schedule(
        completedAtUtc: DateTime.utc(2026, 3, 28, 1),
        oldDueUtc: DateTime.utc(2026, 3, 28, 1, 30),
        oldAnchor: TdfLocalDateTime(2026, 3, 28, 2, 30),
        timeZone: berlin,
      );
      expect(gapStep1.newDueUtc, equals(DateTime.utc(2026, 3, 29, 1, 30)));
      expect(gapStep1.newAnchor, equals(TdfLocalDateTime(2026, 3, 29, 2, 30)));
      final gapStep2 = dailyRule.computeNextMode2Schedule(
        completedAtUtc: DateTime.utc(2026, 3, 29, 1),
        oldDueUtc: gapStep1.newDueUtc,
        oldAnchor: gapStep1.newAnchor,
        timeZone: berlin,
      );
      expect(gapStep2.newDueUtc, equals(DateTime.utc(2026, 3, 30, 0, 30)));
      expect(gapStep2.newAnchor, equals(TdfLocalDateTime(2026, 3, 30, 2, 30)));

      // Overdue completion inside open preparation window omits newSuspendedUtc (null):
      const noLeadMonthly = TaskRepeatRule(count: 1, unit: RepeatUnit.months);
      final overdueOpenWindow = noLeadMonthly.computeNextMode2Schedule(
        completedAtUtc: DateTime.utc(2026, 12, 15, 9),
        oldDueUtc: DateTime.utc(2026, 11, 15, 17),
        oldAnchor: TdfLocalDateTime(2026, 11, 15, 18),
        timeZone: berlin,
      );
      expect(
        overdueOpenWindow.newDueUtc,
        equals(DateTime.utc(2026, 12, 15, 17)),
      );
      expect(
        overdueOpenWindow.newSuspendedUtc,
        isNull,
        reason: 'newSuspended (2026-12-14 23:00 UTC) <= now (2026-12-15 09:00 UTC) must omit suspended immediately',
      );
    });

    test('encodes Base62 entity ID time segment using floor(nowUtcMilliseconds / 1000) across pre-epoch sub-second timestamps (TDF-ID-001)', () {
      final vectors = <({int epochMs, String expectedTime})>[
        (epochMs: -1001, expectedTime: 'zzzy'),
        (epochMs: -1000, expectedTime: 'zzzz'),
        (epochMs: -999, expectedTime: 'zzzz'),
        (epochMs: -500, expectedTime: 'zzzz'),
        (epochMs: -1, expectedTime: 'zzzz'),
        (epochMs: 0, expectedTime: '0000'),
        (epochMs: 500, expectedTime: '0000'),
        (epochMs: 999, expectedTime: '0000'),
        (epochMs: 1000, expectedTime: '0001'),
      ];

      for (final vector in vectors) {
        final timestamp = DateTime.fromMillisecondsSinceEpoch(
          vector.epochMs,
          isUtc: true,
        );
        expect(
          encodeTdfBase62Time(timestamp),
          equals(vector.expectedTime),
          reason:
              'encodeTdfBase62Time(${vector.epochMs}ms) must floor to ${vector.expectedTime}',
        );
        expect(
          generateTaskId(timestamp: timestamp).substring(6),
          equals(vector.expectedTime),
          reason:
              'generateTaskId(${vector.epochMs}ms) suffix must equal ${vector.expectedTime}',
        );
        expect(
          generateLabelId(timestamp: timestamp).substring(6),
          equals(vector.expectedTime),
          reason:
              'generateLabelId(${vector.epochMs}ms) suffix must equal ${vector.expectedTime}',
        );
        expect(
          generateLocationId(timestamp: timestamp).substring(6),
          equals(vector.expectedTime),
          reason:
              'generateLocationId(${vector.epochMs}ms) suffix must equal ${vector.expectedTime}',
        );
      }
    });

    test('redacts TaskLink title and uri in toString()', () {
      const link = TaskLink(
        title: 'Private Runbook',
        uri: 'https://alice:secret@internal.example/runbook?token=xyz',
      );
      final rendered = link.toString();
      expect(
        rendered,
        equals('TaskLink(title: <redacted>, uri: <redacted>)'),
        reason: 'TaskLink.toString must redact both title and uri',
      );
      expect(
        rendered,
        isNot(contains('Private Runbook')),
        reason: 'TaskLink.toString must never leak link title',
      );
      expect(
        rendered,
        isNot(contains('internal.example')),
        reason: 'TaskLink.toString must never leak link uri',
      );
      expect(
        rendered,
        isNot(contains('secret')),
        reason: 'TaskLink.toString must never leak credentials in uri',
      );
    });
  });

  group('Wave 2B Core Engine Invariants (UTF-8 Order, Binary Search, TimeZone Fast Path, TaskItem Reuse)', () {
    test('compareUtf8Strings and TaskHistoryEntry.compareCanonical match exact UTF-8 byte order across BMP, supplementary, and lone surrogates', () {
      int referenceUtf8Compare(String left, String right) {
        final leftBytes = utf8.encode(left);
        final rightBytes = utf8.encode(right);
        final minLength = leftBytes.length < rightBytes.length
            ? leftBytes.length
            : rightBytes.length;
        for (var i = 0; i < minLength; i++) {
          final difference = leftBytes[i].compareTo(rightBytes[i]);
          if (difference != 0) {
            return difference;
          }
        }
        return leftBytes.length.compareTo(rightBytes.length);
      }

      const samples = <String>[
        '',
        'A',
        'AA',
        'B',
        'a',
        'cafe',
        'caf\u00E9',
        'z',
        '\u007F',
        '\u0080',
        '\u07FF',
        '\u0800',
        '\uD7FF',
        '\uE000',
        '\uFFFD',
        '\uFFFF',
        '\u{10000}',
        '\u{10001}',
        '\u{1F600}',
        '\u{10FFFF}',
        'prefix\uE000suffix',
        'prefix\u{10000}suffix',
        '\uD800',
        '\uDC00',
        '\uD800a',
        'a\uDC00',
        '\uD800\uD800',
      ];
      final timestamp = DateTime.utc(2026, 11, 20, 12);

      // UTF-8 byte order places U+E000 (0xEE) before U+10000 (0xF0), opposite to UTF-16 code-unit order.
      expect(
        TdfPayloadComparison.compareUtf8Strings('\uE000', '\u{10000}'),
        lessThan(0),
        reason: 'U+E000 must sort before U+10000 in unsigned UTF-8 byte order',
      );
      expect(
        TdfPayloadComparison.compareUtf8Strings('\uFFFF', '\u{10000}'),
        lessThan(0),
        reason: 'U+FFFF must sort before U+10000 in unsigned UTF-8 byte order',
      );

      for (final left in samples) {
        for (final right in samples) {
          final expected = referenceUtf8Compare(left, right);
          final actual = TdfPayloadComparison.compareUtf8Strings(left, right);
          expect(
            actual.sign,
            equals(expected.sign),
            reason:
                'compareUtf8Strings mismatch for code units ${left.codeUnits} vs ${right.codeUnits}',
          );
          final historyActual = TaskHistoryEntry.compareCanonical(
            TaskHistoryEntry(timestampUtc: timestamp, text: left),
            TaskHistoryEntry(timestampUtc: timestamp, text: right),
          );
          expect(
            historyActual.sign,
            equals(expected.sign),
            reason:
                'TaskHistoryEntry.compareCanonical mismatch for code units ${left.codeUnits} vs ${right.codeUnits}',
          );
        }
      }
    });

    test('TdfDeletedBlock binary search finds first, middle, last, and absent records accurately', () {
      final baseTime = DateTime.utc(2026, 11, 1, 10);
      final taskRecords = <TdfDeletedTaskRecord>[
        for (var i = 0; i < 250; i++)
          TdfDeletedTaskRecord(
            taskId: 'TSK${i.toString().padLeft(7, '0')}',
            deletedAt: baseTime.add(Duration(seconds: i)),
            completionsCheckpoint: i % 5,
          ),
      ];
      final labelRecords = <TdfDeletedLabelRecord>[
        for (var i = 0; i < 100; i++)
          TdfDeletedLabelRecord(
            labelId: 'LBL${i.toString().padLeft(7, '0')}',
            deletedAt: baseTime.add(Duration(seconds: i)),
          ),
      ];
      final locationRecords = <TdfDeletedLocationRecord>[
        for (var i = 0; i < 100; i++)
          TdfDeletedLocationRecord(
            locationId: 'LOC${i.toString().padLeft(7, '0')}',
            deletedAt: baseTime.add(Duration(seconds: i)),
          ),
      ];
      final block = TdfDeletedBlock(
        generation: 3,
        tasks: taskRecords.reversed,
        labels: labelRecords.reversed,
        locations: locationRecords.reversed,
      );

      expect(TdfDeletedBlock.empty.findTaskRecord('TSK0000000'), isNull);
      expect(TdfDeletedBlock.empty.findLabelRecord('LBL0000000'), isNull);
      expect(TdfDeletedBlock.empty.findLocationRecord('LOC0000000'), isNull);

      for (final index in const <int>[0, 1, 124, 125, 248, 249]) {
        final id = 'TSK${index.toString().padLeft(7, '0')}';
        expect(
          block.findTaskRecord(id)?.completionsCheckpoint,
          equals(index % 5),
          reason: 'Binary search must locate task record at index $index',
        );
      }
      expect(block.findTaskRecord('TSK'), isNull);
      expect(block.findTaskRecord('TSK0000124A'), isNull);
      expect(block.findTaskRecord('TSK9999999'), isNull);

      for (final index in const <int>[0, 50, 99]) {
        final labelId = 'LBL${index.toString().padLeft(7, '0')}';
        final locationId = 'LOC${index.toString().padLeft(7, '0')}';
        expect(
          block.findLabelRecord(labelId)?.labelId,
          equals(labelId),
          reason: 'Binary search must locate label record at index $index',
        );
        expect(
          block.findLocationRecord(locationId)?.locationId,
          equals(locationId),
          reason: 'Binary search must locate location record at index $index',
        );
      }
      expect(block.findLabelRecord('LBL9999999'), isNull);
      expect(block.findLocationRecord('LOC9999999'), isNull);
    });

    test('TdfTimeZoneContext reports isolate sendability, fast-paths non-transition sampled probes, and matches analytical America/New_York DST rules', () {
      expect(TdfTimeZoneContext.utc.isIsolateSendable, isTrue);
      expect(TdfTimeZoneContext.europeBerlin.isIsolateSendable, isTrue);
      expect(TdfTimeZoneContext.americaNewYork.isIsolateSendable, isTrue);
      expect(const TdfTimeZoneContext.systemLocal().isIsolateSendable, isTrue);
      expect(
        TdfTimeZoneContext.fixedOffset(const Duration(hours: 2))
            .isIsolateSendable,
        isTrue,
      );
      expect(const TdfTimeZoneContext.missing().isIsolateSendable, isTrue);

      var probeCalls = 0;
      final springTransitionUtcSec =
          DateTime.utc(2026, 3, 8, 7).millisecondsSinceEpoch ~/ 1000;
      final autumnTransitionUtcSec =
          DateTime.utc(2026, 11, 1, 6).millisecondsSinceEpoch ~/ 1000;
      final referenceNewYorkObserver = TdfTimeZoneContext.customObserver(
        'Test/ReferenceNewYork',
        (int utcEpochSeconds) {
          probeCalls++;
          if (utcEpochSeconds >= springTransitionUtcSec &&
              utcEpochSeconds < autumnTransitionUtcSec) {
            return -14400;
          }
          return -18000;
        },
      );
      expect(referenceNewYorkObserver.isIsolateSendable, isFalse);

      // Non-transition date must resolve in at most 4 offset probes via bracketing fast path.
      probeCalls = 0;
      final julyResolved = referenceNewYorkObserver.resolveLocalToUtc(
        2026,
        7,
        15,
        14,
        30,
        0,
      );
      expect(julyResolved, equals(DateTime.utc(2026, 7, 15, 18, 30)));
      expect(
        probeCalls,
        lessThanOrEqualTo(4),
        reason: 'Non-transition sampled resolution must use 3-probe bracketing fast path',
      );

      // Analytical America/New_York must match reference observer across every spring gap and autumn fold minute.
      const newYork = TdfTimeZoneContext.americaNewYork;
      const transitionChecks =
          <({int month, int day, int hour, int minute, int second})>[
            (month: 3, day: 8, hour: 1, minute: 59, second: 59),
            (month: 3, day: 8, hour: 2, minute: 0, second: 0),
            (month: 3, day: 8, hour: 2, minute: 30, second: 0),
            (month: 3, day: 8, hour: 2, minute: 59, second: 59),
            (month: 3, day: 8, hour: 3, minute: 0, second: 0),
            (month: 11, day: 1, hour: 0, minute: 59, second: 59),
            (month: 11, day: 1, hour: 1, minute: 0, second: 0),
            (month: 11, day: 1, hour: 1, minute: 30, second: 0),
            (month: 11, day: 1, hour: 1, minute: 59, second: 59),
            (month: 11, day: 1, hour: 2, minute: 0, second: 0),
            (month: 1, day: 15, hour: 9, minute: 0, second: 0),
            (month: 7, day: 15, hour: 14, minute: 30, second: 0),
          ];
      for (final check in transitionChecks) {
        final analytical = newYork.resolveLocalToUtc(
          2026,
          check.month,
          check.day,
          check.hour,
          check.minute,
          check.second,
        );
        final sampled = referenceNewYorkObserver.resolveLocalToUtc(
          2026,
          check.month,
          check.day,
          check.hour,
          check.minute,
          check.second,
        );
        expect(
          analytical,
          equals(sampled),
          reason:
              'Analytical America/New_York must match sampled observer at 2026-${check.month}-${check.day} ${check.hour}:${check.minute}:${check.second}',
        );
      }
    });

    test('TaskItem.copyWith reuses already-normalized unmodifiable collections when fields are unchanged', () {
      final created = DateTime.utc(2026, 11, 1, 8);
      final original = TaskItem(
        id: '8jKaCdOkD2',
        title: 'Original title',
        createdAt: created,
        labelIds: const <String>['lbl0000001'],
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'dep0000001'),
        ],
        links: const <TaskLink>[
          TaskLink(title: 'Spec', uri: 'https://example.com'),
        ],
        history: <TaskHistoryEntry>[
          TaskHistoryEntry(
            timestampUtc: created.add(const Duration(minutes: 10)),
            text: 'Second',
          ),
          TaskHistoryEntry(
            timestampUtc: created.add(const Duration(minutes: 5)),
            text: 'First',
          ),
        ],
        conditions: const <TaskCondition>[
          LocationTaskCondition(locationIds: <String>['loc0000001']),
        ],
        subtasks: const <SubtaskItem>[SubtaskItem(title: 'Step 1')],
      );

      final copied = original.copyWith(title: 'Updated title');
      expect(copied.title, equals('Updated title'));
      expect(identical(copied.history, original.history), isTrue);
      expect(identical(copied.labelIds, original.labelIds), isTrue);
      expect(identical(copied.dependencies, original.dependencies), isTrue);
      expect(
        identical(copied.blockedByTaskIds, original.blockedByTaskIds),
        isTrue,
      );
      expect(identical(copied.links, original.links), isTrue);
      expect(identical(copied.conditions, original.conditions), isTrue);
      expect(identical(copied.subtasks, original.subtasks), isTrue);
    });
  });
}
