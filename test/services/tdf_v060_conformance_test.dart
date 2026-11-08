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
import 'package:tiertask/models/task_board_evaluator.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_timezone.dart';
import 'package:tiertask/services/tdf_id_migration.dart';
import 'package:tiertask/services/tdf_importer.dart';
import 'package:tiertask/services/tdf_service.dart';

String _specErrorName(TdfErrorKind kind) =>
    '${kind.name[0].toUpperCase()}${kind.name.substring(1)}';

void main() {
  const tdfService = TdfService();
  final fixedDate = DateTime.utc(2026, 11, 1, 12, 0);

  group('TDF 0.6.0 Conformance Suite (spec/conformance/v0.6.0)', () {
    test('passes all parse_valid fixtures, canonical serialization, and canonicalSourceDigest checks', () {
      const baseDir = 'spec/conformance/v0.6.0/parse_valid';
      final manifest = jsonDecode(
        File('$baseDir/manifest.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final cases = manifest['cases'] as List<Object?>;
      expect(cases.length, equals(2));

      for (final rawCase in cases) {
        final testCase = rawCase as Map<String, Object?>;
        final id = testCase['id'] as String;
        final inputFile = testCase['inputFile'] as String;
        final canonicalFile = testCase['canonicalFile'] as String;
        final normalizedFile = testCase['normalizedFile'] as String;

        final inputTdf = File('$baseDir/$inputFile').readAsStringSync();
        final expectedCanonical = File('$baseDir/$canonicalFile')
            .readAsStringSync();
        final normalizedJson = jsonDecode(
          File('$baseDir/$normalizedFile').readAsStringSync(),
        ) as Map<String, Object?>;

        final board = tdfService.parse(inputTdf, evaluationTime: fixedDate);
        final serialized = tdfService.serialize(board);
        expect(
          serialized,
          equals(expectedCanonical),
          reason: 'Canonical output mismatch for $id',
        );

        final digest = TdfIdMigration.sha256Hex(utf8.encode(serialized));
        expect(
          digest,
          equals(normalizedJson['canonicalSourceDigest']),
          reason: 'canonicalSourceDigest mismatch for $id',
        );

        if (id == '01_complete_v060') {
          expect(board.deletedBlock.locations.length, equals(1));
          expect(
            board.deletedBlock.locations.single.locationId,
            equals('8tYp4M0eF3'),
          );
          expect(
            board.locations.map((loc) => loc.id),
            equals(['7pQr9mOkD2', '5473OnNDhL']),
          );
          final warehouse = board.findLocation('5473OnNDhL')!;
          expect(warehouse.latitudeText, equals('0'));
          expect(warehouse.longitudeText, equals('13.405'));
          expect(warehouse.radiusText, equals('75.5'));
          expect(warehouse.effectiveModifiedAt, equals(DateTime.utc(1970)));

          final mowTask = board.findTask('8jKaCdOkD2')!;
          expect(mowTask.dueAt, equals(DateTime.utc(2026, 11, 7, 16, 0)));
          expect(
            mowTask.origin,
            equals(
              const TaskOrigin(
                namespace: 'https://jira.example.com',
                externalKey: 'HOME-99',
              ),
            ),
          );
          final locCond = mowTask.conditions
              .whereType<LocationTaskCondition>()
              .single;
          expect(
            locCond.locationIds,
            equals(['7pQr9mOkD2', '5473OnNDhL']),
            reason: 'Coalesced location IDs must preserve first-seen declaration order',
          );
        } else if (id == '02_scoped_labels_and_shared_origin') {
          final evalMap =
              normalizedJson['globalViewEvaluation'] as Map<String, Object?>;
          final labelsById = {
            for (final label in board.labels) label.id: label,
          };
          for (final entry in evalMap.entries) {
            final task = board.findTask(entry.key)!;
            final expected = entry.value as Map<String, Object?>;
            expect(
              TaskBoardEvaluator.isRestrictedFromGlobalView(task, labelsById),
              equals(expected['isRestrictedFromGlobalView']),
              reason: 'isRestrictedFromGlobalView mismatch for ${entry.key}',
            );
          }
        }
      }
    });

    test('passes all 23 parse_invalid fixtures with exact TdfErrorKind and line number', () {
      const baseDir = 'spec/conformance/v0.6.0/parse_invalid';
      final manifest = jsonDecode(
        File('$baseDir/manifest.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final cases = manifest['cases'] as List<Object?>;
      expect(cases.length, equals(23));

      for (final rawCase in cases) {
        final testCase = rawCase as Map<String, Object?>;
        final file = testCase['file'] as String;
        final expectedError = testCase['expectedError'] as String;
        final expectedLine = testCase['expectedLine'] as int;
        final inputTdf = File('$baseDir/$file').readAsStringSync();

        expect(
          () => tdfService.parse(inputTdf, evaluationTime: fixedDate),
          throwsA(
            isA<TdfException>()
                .having(
                  (error) => _specErrorName(error.kind),
                  'kind',
                  expectedError,
                )
                .having((error) => error.line, 'line', expectedLine),
          ),
          reason:
              'Fixture $file must fail with $expectedError at line $expectedLine',
        );
      }
    });

    test('passes all 13 bounds fixtures', () {
      const baseDir = 'spec/conformance/v0.6.0/bounds';
      final manifest = jsonDecode(
        File('$baseDir/manifest.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final cases = manifest['cases'] as List<Object?>;
      expect(cases.length, equals(13));

      for (final rawCase in cases) {
        final testCase = rawCase as Map<String, Object?>;
        final file = testCase['file'] as String;
        final isValid = testCase['valid'] as bool;
        final expectedError = testCase['expectedError'] as String?;
        final inputTdf = File('$baseDir/$file').readAsStringSync();

        if (isValid) {
          expect(
            () => tdfService.parse(inputTdf, evaluationTime: fixedDate),
            returnsNormally,
            reason: 'Valid bounds fixture $file must be accepted',
          );
        } else {
          expect(
            () => tdfService.parse(inputTdf, evaluationTime: fixedDate),
            throwsA(
              isA<TdfException>().having(
                (error) => _specErrorName(error.kind),
                'kind',
                expectedError,
              ),
            ),
            reason:
                'Invalid bounds fixture $file must fail with $expectedError',
          );
        }
      }
    });

    test('passes all migration fixtures and Section 10.7.1 normative location ID vectors', () {
      const baseDir = 'spec/conformance/v0.6.0/migration';
      final manifest = jsonDecode(
        File('$baseDir/manifest.json').readAsStringSync(),
      ) as Map<String, Object?>;

      final idVectors = manifest['normativeLocationIdVectors'] as List<Object?>;
      expect(idVectors.length, equals(4));
      for (final rawVec in idVectors) {
        final vec = rawVec as Map<String, Object?>;
        final sourceId = vec['sourceId'] as String;
        final counter = vec['counter'] as int;
        final expectedCandidate = vec['candidate'] as String;
        final usedIds = <String>{if (counter == 1) '5473OnNDhL'};
        final assigned = TdfIdMigration.assignLocationId(
          canonicalTuple: sourceId,
          usedIds: usedIds,
        );
        expect(
          assigned,
          equals(expectedCandidate),
          reason:
              'Location ID vector mismatch for $sourceId (counter=$counter)',
        );
      }

      final cases = manifest['cases'] as List<Object?>;
      expect(cases.length, equals(3));
      for (final rawCase in cases) {
        final testCase = rawCase as Map<String, Object?>;
        final id = testCase['id'] as String;
        final inputFile = testCase['inputFile'] as String;
        final isValid = testCase['valid'] as bool;
        final inputTdf = File('$baseDir/$inputFile').readAsStringSync();

        if (isValid) {
          final expectedFile = testCase['expectedFile'] as String;
          final expectedTdf = File('$baseDir/$expectedFile').readAsStringSync();

          final parsedViaLoad = tdfService.parse(
            inputTdf,
            evaluationTime: fixedDate,
          );
          final serializedFromLoad = tdfService.serialize(parsedViaLoad);
          expect(
            serializedFromLoad,
            equals(expectedTdf),
            reason: 'Load-time conversion mismatch for $id',
          );

          final imported = TdfImporter.importDocument(
            inputTdf,
            evaluationTime: fixedDate,
          );
          expect(
            imported.migratedTdfContent,
            equals(expectedTdf),
            reason: 'Explicit TdfImporter migration mismatch for $id',
          );
        } else {
          final expectedError = testCase['expectedError'] as String;
          final expectedLine = testCase['expectedLine'] as int;
          expect(
            () => tdfService.parse(inputTdf, evaluationTime: fixedDate),
            throwsA(
              isA<TdfException>()
                  .having(
                    (error) => _specErrorName(error.kind),
                    'kind',
                    expectedError,
                  )
                  .having((error) => error.line, 'line', expectedLine),
            ),
            reason:
                'Invalid migration fixture $id must fail with $expectedError at line $expectedLine',
          );
        }
      }
    });

    test(
      'passes all timezone conversion and schedule-anchored recurrence vectors',
      () {
        const baseDir = 'spec/conformance/v0.6.0/timezone';
        final manifest = jsonDecode(
          File('$baseDir/vectors.json').readAsStringSync(),
        ) as Map<String, Object?>;
        const tz = TdfTimeZoneContext.europeBerlin;

        DateTime parseSpecDateTime(String raw) {
          final parts = raw.split(' ');
          final d = parts[0].split('-').map(int.parse).toList();
          final t = parts[1].split(':').map(int.parse).toList();
          return DateTime.utc(d[0], d[1], d[2], t[0], t[1], t[2]);
        }

        final conversionVectors =
            manifest['conversionVectors'] as List<Object?>;
        expect(conversionVectors.length, equals(4));
        for (final rawVec in conversionVectors) {
          final vec = rawVec as Map<String, Object?>;
          final localInput = parseSpecDateTime(vec['localInput'] as String);
          final expectedUtc = parseSpecDateTime(vec['expectedUtc'] as String);
          final actualUtc = tz.resolveLocalToUtc(
            localInput.year,
            localInput.month,
            localInput.day,
            localInput.hour,
            localInput.minute,
            localInput.second,
          );
          expect(
            actualUtc,
            equals(expectedUtc),
            reason: 'Conversion vector mismatch for ${vec['localInput']}',
          );
        }

        final recurrenceVectors =
            manifest['recurrenceDueAndSuspendedVectors'] as List<Object?>;
        expect(recurrenceVectors.length, equals(4));
        for (final rawVec in recurrenceVectors) {
          final vec = rawVec as Map<String, Object?>;
          final id = vec['id'] as String;
          final completionUtc = parseSpecDateTime(
            vec['completionInstantUtc'] as String,
          );
          final prevDueLocal = parseSpecDateTime(
            vec['previousDueLocal'] as String,
          );
          final prevDueUtc = tz.resolveLocalToUtc(
            prevDueLocal.year,
            prevDueLocal.month,
            prevDueLocal.day,
            prevDueLocal.hour,
            prevDueLocal.minute,
            prevDueLocal.second,
          );
          final prevSuspendedLocalRaw =
              vec['previousSuspendedLocal'] as String?;
          DateTime? prevSuspendedUtc;
          if (prevSuspendedLocalRaw != null) {
            final prevSuspendedLocal = parseSpecDateTime(prevSuspendedLocalRaw);
            prevSuspendedUtc = tz.resolveLocalToUtc(
              prevSuspendedLocal.year,
              prevSuspendedLocal.month,
              prevSuspendedLocal.day,
              prevSuspendedLocal.hour,
              prevSuspendedLocal.minute,
              prevSuspendedLocal.second,
            );
          }

          const rule = TaskRepeatRule(
            count: 1,
            unit: RepeatUnit.months,
            clock: TdfRepeatClock.midnight,
          );
          final result = rule.nextScheduleAnchoredOccurrence(
            completedAtUtc: completionUtc,
            oldDueUtc: prevDueUtc,
            oldSuspendedUtc: prevSuspendedUtc,
            timeZone: tz,
          );
          expect(
            result.newDueUtc,
            equals(parseSpecDateTime(vec['expectedNewDueUtc'] as String)),
            reason: 'expectedNewDueUtc mismatch for $id',
          );
          expect(
            result.newSuspendedUtc,
            equals(parseSpecDateTime(vec['expectedNewSuspendedUtc'] as String)),
            reason: 'expectedNewSuspendedUtc mismatch for $id',
          );
        }
      },
    );
  });
}
