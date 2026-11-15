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
        final nextOccurrence = rule.nextLegacy060ScheduleAnchoredOccurrence(
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

    test('exposes DueLeadWindow variants, fromId fallback, and WebDavConfig dueLeadWindow copyWith/equality/toString', () {
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

      final expectedSpecs = <(DueLeadWindow, int, Duration?)>[
        (DueLeadWindow.off, 0, null),
        (DueLeadWindow.atDue, 1, Duration.zero),
        (DueLeadWindow.hours12, 2, const Duration(hours: 12)),
        (DueLeadWindow.hours24, 3, const Duration(hours: 24)),
        (DueLeadWindow.hours48, 4, const Duration(hours: 48)),
        (DueLeadWindow.days7, 5, const Duration(days: 7)),
      ];
      for (final (window, expectedId, expectedDuration) in expectedSpecs) {
        expect(
          window.id,
          equals(expectedId),
          reason: '${window.name} id must equal $expectedId',
        );
        expect(
          window.duration,
          equals(expectedDuration),
          reason: '${window.name} duration must equal $expectedDuration',
        );
        expect(
          DueLeadWindow.fromId(expectedId),
          equals(window),
          reason: 'fromId($expectedId) must resolve to ${window.name}',
        );
      }

      expect(
        DueLeadWindow.fromId(99),
        equals(DueLeadWindow.hours24),
        reason: 'Out-of-range positive ID must fall back to hours24',
      );
      expect(
        DueLeadWindow.fromId(-1),
        equals(DueLeadWindow.hours24),
        reason: 'Negative ID must fall back to hours24',
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
  });

  group('TDF 0.7.0 Primitives, Bounds, TdfLabel Links, TaskHistoryEntry & TaskItem Ownership', () {
    test(
      'exposes TDF 0.7.0 structural resource bounds and TdfSchemaVersion enum',
      () {
        expect(maxTdfStmtsPerBlock, equals(1024));
        expect(maxTdfLegacy060StmtsPerBlock, equals(512));
        expect(maxTdfLinksPerLabel, equals(20));
        expect(maxTdfHistoryPerTask, equals(500));
        expect(
          TdfSchemaVersion.values,
          equals(const <TdfSchemaVersion>[
            TdfSchemaVersion.v060,
            TdfSchemaVersion.v070,
          ]),
        );
      },
    );

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
        modifiedAt: DateTime.utc(2026, 11, 1, 10, 0),
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
      final febOccurrence = ruleWithLeadAndClock.nextScheduleAnchoredOccurrence(
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
        febOccurrence.newSuspendedUtc,
        equals(berlin.resolveLocalToUtc(2026, 2, 23, 9, 30, 0)),
      );

      // Clamping when leadDays == 0 and repeat clock (20:00) is later on the same day than due (10:00):
      const lateClockRule = TaskRepeatRule(
        count: 1,
        unit: RepeatUnit.days,
        clock: TdfRepeatClock(hour: 20, minute: 0),
        leadDays: 0,
      );
      final morningDue = DateTime.utc(2026, 11, 1, 10, 0);
      final clamped = lateClockRule.nextScheduleAnchoredOccurrence(
        completedAtUtc: DateTime.utc(2026, 11, 1, 8, 0),
        oldDueUtc: morningDue,
        timeZone: TdfTimeZoneContext.utc,
      );
      expect(clamped.newDueUtc, equals(DateTime.utc(2026, 11, 2, 10, 0)));
      expect(
        clamped.newSuspendedUtc,
        equals(DateTime.utc(2026, 11, 2, 10, 0)),
        reason: 'candidateSuspended > newDue must clamp newSuspendedUtc to newDueUtc',
      );

      // Subtracting leadDays before year 0001 must throw TdfException(invalidTimestamp):
      const hugeLeadRule = TaskRepeatRule(
        count: 1,
        unit: RepeatUnit.days,
        leadDays: 10,
      );
      expect(
        () => hugeLeadRule.nextScheduleAnchoredOccurrence(
          completedAtUtc: DateTime.utc(1, 1, 1, 0, 0),
          oldDueUtc: DateTime.utc(1, 1, 2, 12, 0),
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
      final now = DateTime.utc(2026, 11, 1, 12, 0, 0);

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
        isDuePassive: false,
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
              TdfTaskDependency(taskId: 'dep0000001', requiredCompletion: 1),
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
          TdfTaskDependency(taskId: 'dep0000001', requiredCompletion: 1),
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
}
