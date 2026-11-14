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
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/tdf_timezone.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/services/tdf_id_migration.dart';

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
      expect(nineAm, equals(const TdfRepeatClock(hour: 9, minute: 0)));
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
        equals(DateTime.utc(2026, 3, 28, 8, 0, 0)),
        reason: '2026-03-28 09:00:00 CET (UTC+1) -> 2026-03-28 08:00:00 UTC',
      );
      expect(
        zone.resolveLocalToUtc(2026, 3, 29, 9, 0, 0),
        equals(DateTime.utc(2026, 3, 29, 7, 0, 0)),
        reason: '2026-03-29 09:00:00 CEST (UTC+2) -> 2026-03-29 07:00:00 UTC',
      );
      expect(
        zone.resolveLocalToUtc(2026, 3, 29, 2, 30, 0),
        equals(DateTime.utc(2026, 3, 29, 1, 30, 0)),
        reason: '2026-03-29 02:30:00 falls in spring-forward gap -> pre-gap UTC+1 -> 01:30:00 UTC (03:30:00 CEST)',
      );
      expect(
        zone.toLocalWallClock(DateTime.utc(2026, 3, 29, 1, 30, 0)),
        equals(DateTime.utc(2026, 3, 29, 3, 30, 0)),
        reason:
            'Resolved 2026-03-29 01:30:00 UTC is 03:30:00 local after the gap',
      );
      expect(
        zone.resolveLocalToUtc(2026, 3, 30, 2, 30, 0),
        equals(DateTime.utc(2026, 3, 30, 0, 30, 0)),
        reason: '2026-03-30 02:30:00 CEST (UTC+2) -> 2026-03-30 00:30:00 UTC',
      );
      expect(
        zone.resolveLocalToUtc(2026, 10, 25, 2, 30, 0),
        equals(DateTime.utc(2026, 10, 25, 0, 30, 0)),
        reason: '2026-10-25 02:30:00 occurs twice during fall-back overlap -> first occurrence (UTC+2) -> 00:30:00 UTC',
      );
      expect(
        zone.resolveLocalToUtc(2026, 10, 25, 9, 0, 0),
        equals(DateTime.utc(2026, 10, 25, 8, 0, 0)),
        reason: '2026-10-25 09:00:00 CET (UTC+1) -> 2026-10-25 08:00:00 UTC',
      );
      expect(
        zone.resolveLocalToUtc(2026, 11, 5, 0, 0, 0),
        equals(DateTime.utc(2026, 11, 4, 23, 0, 0)),
        reason: '2026-11-05 00:00:00 CET (UTC+1) -> 2026-11-04 23:00:00 UTC',
      );
    });

    test('computes next due UTC instant for TaskRepeatRule across DST and month-end boundaries and enforces TimeZoneContextRequired', () {
      const dailyAt0230 = TaskRepeatRule(
        count: 1,
        unit: RepeatUnit.days,
        clock: TdfRepeatClock(hour: 2, minute: 30),
      );
      final completedOnMar28Utc = DateTime.utc(2026, 3, 28, 10, 0, 0);
      final nextDueGapUtc = dailyAt0230.nextDueUtc(
        completedAtUtc: completedOnMar28Utc,
        timeZone: TdfTimeZoneContext.europeBerlin,
      );
      expect(
        nextDueGapUtc,
        equals(DateTime.utc(2026, 3, 29, 1, 30, 0)),
        reason: 'Completing on 2026-03-28 schedules 2026-03-29 02:30 local -> 01:30 UTC via pre-gap offset',
      );
      expect(
        dailyAt0230.clock,
        equals(const TdfRepeatClock(hour: 2, minute: 30)),
        reason: 'Repeat rule clock must remain 02:30 after gap adjustment',
      );

      final nextDueMar30Utc = dailyAt0230.nextDueUtc(
        completedAtUtc: DateTime.utc(2026, 3, 29, 10, 0, 0),
        timeZone: TdfTimeZoneContext.europeBerlin,
      );
      expect(
        nextDueMar30Utc,
        equals(DateTime.utc(2026, 3, 30, 0, 30, 0)),
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
          const TdfTaskDependency(taskId: '3nQp7ROkB8', requiredCompletion: 1),
          const TdfTaskDependency(taskId: '8jKaCdOkD2', requiredCompletion: 5),
        ]);
        expect(
          deduplicated,
          equals(const <TdfTaskDependency>[
            TdfTaskDependency(taskId: '3nQp7ROkB8', requiredCompletion: 1),
            TdfTaskDependency(taskId: '8jKaCdOkD2', requiredCompletion: 5),
          ]),
          reason: 'Deduplication must retain greatest requirement and sort by ascending ASCII ID',
        );
      });

      test('unstamped TdfLabel effectiveModifiedAt defaults to Unix epoch 1970-01-01 00:00:00 UTC', () {
        const label = TdfLabel(id: '4x9p2mOkD2', name: 'Home');
        expect(
          label.effectiveModifiedAt,
          equals(DateTime.utc(1970, 1, 1, 0, 0, 0)),
          reason: 'Section 6.7.2 requires unstamped labels to use 1970-01-01 00:00:00 UTC',
        );
      });
    },
  );

  group('TDF 0.5.0 Section 10.4.4 Deterministic SHA-256 Base62 ID Migration Vectors', () {
    test('matches all normative Section 10.4.4 test vectors', () {
      expect(
        TdfIdMigration.deriveCandidateId(
          namespace: 'label',
          sourceId: 'home',
          counter: 0,
        ),
        equals('e2Mz9WqsjC'),
      );
      expect(
        TdfIdMigration.deriveCandidateId(
          namespace: 'label',
          sourceId: 't001',
          counter: 0,
        ),
        equals('Nb0QaFXPe7'),
      );
      expect(
        TdfIdMigration.deriveCandidateId(
          namespace: 'task',
          sourceId: 'home',
          counter: 0,
        ),
        equals('vK4z80gnew'),
      );
      expect(
        TdfIdMigration.deriveCandidateId(
          namespace: 'task',
          sourceId: 't001',
          counter: 0,
        ),
        equals('OaPtpMHEy3'),
      );
      expect(
        TdfIdMigration.deriveCandidateId(
          namespace: 'task',
          sourceId: 't001',
          counter: 1,
        ),
        equals('ohlr11vwDl'),
      );
      expect(
        TdfIdMigration.deriveCandidateId(
          namespace: 'task',
          sourceId: 'T001',
          counter: 0,
        ),
        equals('mXscM7kwvs'),
      );
      expect(
        TdfIdMigration.deriveCandidateId(
          namespace: 'task',
          sourceId: 'gone',
          counter: 0,
        ),
        equals('5OhMnA4x2F'),
      );
    });

    test('increments counter on collision with existing canonical ID and fails with MigrationIdentifierCollision when counters 0..255 are exhausted', () {
      final mapping = TdfIdMigration.buildMigrationMap(
        existingCanonicalIds: const <String>{'OaPtpMHEy3'},
        nonCanonicalLabelIds: const <String>{'home'},
        nonCanonicalTaskIds: const <String>{'t001', 'gone'},
      );
      expect(mapping.labelIds['home'], equals('e2Mz9WqsjC'));
      expect(
        mapping.taskIds['t001'],
        equals('ohlr11vwDl'),
        reason: 'Counter 0 (OaPtpMHEy3) is already in existingCanonicalIds, so counter 1 (ohlr11vwDl) must be selected',
      );
      expect(mapping.taskIds['gone'], equals('5OhMnA4x2F'));

      final all256Candidates = <String>{
        for (var i = 0; i < 256; i++)
          TdfIdMigration.deriveCandidateId(
            namespace: 'task',
            sourceId: 't001',
            counter: i,
          ),
      };
      expect(
        () => TdfIdMigration.buildMigrationMap(
          existingCanonicalIds: all256Candidates,
          nonCanonicalLabelIds: const <String>{},
          nonCanonicalTaskIds: const <String>{'t001'},
        ),
        throwsA(
          isA<TdfContextException>().having(
            (error) => error.kind,
            'kind',
            TdfContextOutcomeKind.migrationIdentifierCollision,
          ),
        ),
        reason: 'Exhausting all 256 counters must fail with MigrationIdentifierCollision',
      );
    });
  });

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

      const migrationErr = TdfException(
        kind: TdfErrorKind.limitExceeded,
        line: 3,
        message: 'Too many blocks',
        sourceVersion: '0.4.0',
        targetVersion: '0.5.0',
      );
      expect(
        migrationErr.toString(),
        equals(
          'TdfException(limitExceeded, 0.4.0->0.5.0, line 3): Too many blocks',
        ),
      );
      expect(maxTdfBlocksPerDoc, equals(4096));
    });
  });

  group('TDF 0.6.0 Timezone Conversion & Mode 2 Schedule-Anchored Recurrence Vectors', () {
    test('passes all conversion and recurrenceDueAndSuspendedVectors in spec/conformance/v0.6.0/timezone/vectors.json', () {
      final rawJson = File('spec/conformance/v0.6.0/timezone/vectors.json')
          .readAsStringSync();
      final decoded = jsonDecode(rawJson) as Map<String, Object?>;
      final conversionVectors = decoded['conversionVectors'] as List<Object?>;
      for (final entry in conversionVectors) {
        final vector = entry as Map<String, Object?>;
        final localInput = vector['localInput'] as String;
        final expectedUtc = vector['expectedUtc'] as String;
        final parsedLocal = TaskItem.tryParseTdfTimestampInput(localInput)!;
        final resolvedUtc = TdfTimeZoneContext.europeBerlin.resolveLocalToUtc(
          parsedLocal.year,
          parsedLocal.month,
          parsedLocal.day,
          parsedLocal.hour,
          parsedLocal.minute,
          parsedLocal.second,
        );
        expect(
          TaskItem.formatTdfTimestampWithSeconds(resolvedUtc),
          equals(expectedUtc),
          reason: 'Conversion vector $localInput (${vector["note"]})',
        );
      }

      final recurrenceVectors =
          decoded['recurrenceDueAndSuspendedVectors'] as List<Object?>;
      for (final entry in recurrenceVectors) {
        final vector = entry as Map<String, Object?>;
        final id = vector['id'] as String;
        final completionUtc = TaskItem.tryParseTdfTimestampInput(
          vector['completionInstantUtc'] as String,
        )!;
        final prevDueLocal = TaskItem.tryParseTdfTimestampInput(
          vector['previousDueLocal'] as String,
        )!;
        final prevDueUtc = TdfTimeZoneContext.europeBerlin.resolveLocalToUtc(
          prevDueLocal.year,
          prevDueLocal.month,
          prevDueLocal.day,
          prevDueLocal.hour,
          prevDueLocal.minute,
          prevDueLocal.second,
        );
        final rawPrevSuspLocal = vector['previousSuspendedLocal'] as String?;
        final DateTime? prevSuspUtc;
        if (rawPrevSuspLocal != null) {
          final parsedSuspLocal = TaskItem.tryParseTdfTimestampInput(
            rawPrevSuspLocal,
          )!;
          prevSuspUtc = TdfTimeZoneContext.europeBerlin.resolveLocalToUtc(
            parsedSuspLocal.year,
            parsedSuspLocal.month,
            parsedSuspLocal.day,
            parsedSuspLocal.hour,
            parsedSuspLocal.minute,
            parsedSuspLocal.second,
          );
        } else {
          prevSuspUtc = null;
        }

        const rule = TaskRepeatRule(count: 1, unit: RepeatUnit.months);
        final nextOccurrence = rule.nextScheduleAnchoredOccurrence(
          completedAtUtc: completionUtc,
          oldDueUtc: prevDueUtc,
          oldSuspendedUtc: prevSuspUtc,
          timeZone: TdfTimeZoneContext.europeBerlin,
        );
        expect(
          nextOccurrence.stepsK,
          equals(vector['advancementStepsK'] as int),
          reason: 'Vector $id must advance by expected k steps',
        );
        expect(
          TaskItem.formatTdfTimestampWithSeconds(nextOccurrence.newDueUtc),
          equals(vector['expectedNewDueUtc'] as String),
          reason: 'Vector $id expectedNewDueUtc',
        );
        expect(
          TaskItem.formatTdfTimestampWithSeconds(
            nextOccurrence.newSuspendedUtc,
          ),
          equals(vector['expectedNewSuspendedUtc'] as String),
          reason: 'Vector $id expectedNewSuspendedUtc',
        );
      }
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
        themePalette: AppThemePalette.navy,
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
  });
}
