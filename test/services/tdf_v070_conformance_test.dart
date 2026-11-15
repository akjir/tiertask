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
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/tdf_timezone.dart';
import 'package:tiertask/services/tdf_id_migration.dart';
import 'package:tiertask/services/tdf_importer.dart';
import 'package:tiertask/services/tdf_service.dart';

String _specErrorName(TdfErrorKind kind) =>
    '${kind.name[0].toUpperCase()}${kind.name.substring(1)}';

DateTime _parseSpecDateTime(String raw) {
  final parts = raw.split(' ');
  final dateParts = parts[0].split('-').map(int.parse).toList();
  final timeParts = parts[1].split(':').map(int.parse).toList();
  return DateTime.utc(
    dateParts[0],
    dateParts[1],
    dateParts[2],
    timeParts[0],
    timeParts[1],
    timeParts[2],
  );
}

RepeatUnit _parseRepeatUnit(String raw) => switch (raw) {
  'days' => RepeatUnit.days,
  'weeks' => RepeatUnit.weeks,
  'months' => RepeatUnit.months,
  _ => throw ArgumentError('Unexpected repeat unit: $raw'),
};

void _verifyNormalizedBoard(
  TaskBoard board,
  Map<String, Object?> normalizedJson,
  String caseId,
) {
  final deletedJson = normalizedJson['deleted'] as Map<String, Object?>;
  expect(
    board.deletedBlock.generation,
    equals(deletedJson['generation']),
    reason: 'deleted.generation mismatch for $caseId',
  );
  final deletedTasksJson = deletedJson['tasks'] as List<Object?>;
  expect(board.deletedBlock.tasks.length, equals(deletedTasksJson.length));
  for (var i = 0; i < deletedTasksJson.length; i++) {
    final expected = deletedTasksJson[i] as Map<String, Object?>;
    final actual = board.deletedBlock.tasks[i];
    expect(actual.taskId, equals(expected['id']));
    expect(
      actual.deletedAt,
      equals(DateTime.parse(expected['deletedAt'] as String)),
    );
    expect(
      actual.completionsCheckpoint,
      equals(expected['completionsCheckpoint']),
    );
  }

  final deletedLabelsJson = deletedJson['labels'] as List<Object?>;
  expect(board.deletedBlock.labels.length, equals(deletedLabelsJson.length));
  for (var i = 0; i < deletedLabelsJson.length; i++) {
    final expected = deletedLabelsJson[i] as Map<String, Object?>;
    final actual = board.deletedBlock.labels[i];
    expect(actual.labelId, equals(expected['id']));
    expect(
      actual.deletedAt,
      equals(DateTime.parse(expected['deletedAt'] as String)),
    );
  }

  final deletedLocationsJson = deletedJson['locations'] as List<Object?>;
  expect(
    board.deletedBlock.locations.length,
    equals(deletedLocationsJson.length),
  );
  for (var i = 0; i < deletedLocationsJson.length; i++) {
    final expected = deletedLocationsJson[i] as Map<String, Object?>;
    final actual = board.deletedBlock.locations[i];
    expect(actual.locationId, equals(expected['id']));
    expect(
      actual.deletedAt,
      equals(DateTime.parse(expected['deletedAt'] as String)),
    );
  }

  final queueJson = normalizedJson['queue'] as Map<String, Object?>;
  expect(
    board.queueBlock.modifiedAt,
    equals(DateTime.parse(queueJson['modified'] as String)),
    reason: 'queue.modified mismatch for $caseId',
  );
  expect(
    board.queueBlock.taskIds,
    equals(queueJson['taskIds']),
    reason: 'queue.taskIds mismatch for $caseId',
  );

  final labelsJson = normalizedJson['labels'] as List<Object?>;
  expect(board.labels.length, equals(labelsJson.length));
  for (final rawLabel in labelsJson) {
    final expected = rawLabel as Map<String, Object?>;
    final labelId = expected['id'] as String;
    final actual = board.findLabel(labelId);
    expect(actual, isNotNull, reason: 'Missing label $labelId in $caseId');
    if (actual == null) continue;
    expect(actual.isScoped, equals(expected['scoped']));
    expect(actual.name, equals(expected['name']));
    expect(actual.color, equals(expected['color']));
    expect(actual.note, equals(expected['note']));
    expect(
      actual.effectiveModifiedAt,
      equals(DateTime.parse(expected['modified'] as String)),
    );
    final expectedLinks = (expected['links'] as List<Object?>)
        .map((item) => item as Map<String, Object?>)
        .map(
          (item) => TaskLink(
            title: item['title'] as String,
            uri: item['uri'] as String,
          ),
        )
        .toList();
    expect(
      actual.links,
      equals(expectedLinks),
      reason: 'label.links mismatch for $labelId in $caseId',
    );
  }

  final locationsJson = normalizedJson['locations'] as List<Object?>;
  expect(board.locations.length, equals(locationsJson.length));
  for (final rawLoc in locationsJson) {
    final expected = rawLoc as Map<String, Object?>;
    final locId = expected['id'] as String;
    final actual = board.findLocation(locId);
    expect(actual, isNotNull, reason: 'Missing location $locId in $caseId');
    if (actual == null) continue;
    expect(actual.name, equals(expected['name']));
    expect(actual.note, equals(expected['note']));
    expect(actual.source, equals(expected['source']));
    final coords = expected['coordinates'] as Map<String, Object?>;
    expect(actual.latitudeText, equals(coords['latitude']));
    expect(actual.longitudeText, equals(coords['longitude']));
    expect(actual.radiusText, equals(expected['radius']));
    expect(
      actual.effectiveModifiedAt,
      equals(DateTime.parse(expected['modified'] as String)),
    );
  }

  final tasksJson = normalizedJson['tasks'] as List<Object?>;
  expect(board.allTasks.length, equals(tasksJson.length));
  for (final rawTask in tasksJson) {
    final expected = rawTask as Map<String, Object?>;
    final taskId = expected['id'] as String;
    final actual = board.findTask(taskId);
    expect(actual, isNotNull, reason: 'Missing task $taskId in $caseId');
    if (actual == null) continue;
    expect(actual.isPriority, equals(expected['priority']));
    expect(actual.title, equals(expected['name']));
    expect(actual.note, equals(expected['note']));
    expect(
      actual.createdAt,
      equals(DateTime.parse(expected['created'] as String)),
    );
    final finishedStr = expected['finished'] as String?;
    expect(
      actual.completedAt,
      equals(finishedStr != null ? DateTime.parse(finishedStr) : null),
    );
    expect(
      actual.effectiveModifiedAt,
      equals(DateTime.parse(expected['modified'] as String)),
    );
    expect(actual.completions, equals(expected['completions']));

    final repeatJson = expected['repeat'] as Map<String, Object?>?;
    if (repeatJson == null) {
      expect(actual.repeatRule, isNull);
    } else {
      final atStr = repeatJson['at'] as String?;
      final expectedClock = atStr == null
          ? TdfRepeatClock.midnight
          : TdfRepeatClock.tryParse(atStr);
      expect(
        actual.repeatRule,
        equals(
          TaskRepeatRule(
            count: repeatJson['count'] as int,
            unit: _parseRepeatUnit(repeatJson['unit'] as String),
            clock: expectedClock ?? TdfRepeatClock.midnight,
            leadDays: repeatJson['leadDays'] as int,
          ),
        ),
        reason: 'repeatRule mismatch for $taskId in $caseId',
      );
    }

    expect(actual.labelIds, equals(expected['labels']));

    final blockedJson = expected['blocked'] as List<Object?>;
    final expectedDeps = blockedJson
        .map((item) => item as Map<String, Object?>)
        .map(
          (item) => TdfTaskDependency(
            taskId: item['targetId'] as String,
            requiredCompletion: item['requiredCompletions'] as int,
          ),
        )
        .toList();
    expect(actual.dependencies, equals(expectedDeps));

    final suspendedJson = expected['suspended'] as Map<String, Object?>?;
    if (suspendedJson == null) {
      expect(actual.isSuspendedForever, isFalse);
      expect(actual.suspendedAt, isNull);
      expect(actual.suspendedNote, isNull);
    } else {
      expect(actual.isSuspendedForever, equals(suspendedJson['forever']));
      final tsStr = suspendedJson['timestamp'] as String?;
      expect(
        actual.suspendedAt,
        equals(tsStr != null ? DateTime.parse(tsStr) : null),
      );
      expect(
        actual.suspendedNote,
        equals(suspendedJson['note']),
        reason: 'suspendedNote mismatch for $taskId in $caseId',
      );
    }

    final dueJson = expected['due'] as Map<String, Object?>?;
    if (dueJson == null) {
      expect(actual.dueAt, isNull);
      expect(actual.isDuePassive, isFalse);
      expect(actual.dueNote, isNull);
    } else {
      expect(
        actual.dueAt,
        equals(DateTime.parse(dueJson['timestamp'] as String)),
      );
      expect(
        actual.isDuePassive,
        equals(dueJson['passive']),
        reason: 'isDuePassive mismatch for $taskId in $caseId',
      );
      expect(
        actual.dueNote,
        equals(dueJson['note']),
        reason: 'dueNote mismatch for $taskId in $caseId',
      );
    }

    final originJson = expected['origin'] as Map<String, Object?>?;
    if (originJson == null) {
      expect(actual.origin, isNull);
    } else {
      expect(
        actual.origin,
        equals(
          TaskOrigin(
            namespace: originJson['namespace'] as String,
            externalKey: originJson['externalKey'] as String,
          ),
        ),
      );
    }

    final expectedLinks = (expected['links'] as List<Object?>)
        .map((item) => item as Map<String, Object?>)
        .map(
          (item) => TaskLink(
            title: item['title'] as String,
            uri: item['uri'] as String,
          ),
        )
        .toList();
    expect(actual.links, equals(expectedLinks));

    final expectedHistory = (expected['history'] as List<Object?>)
        .map((item) => item as Map<String, Object?>)
        .map(
          (item) => TaskHistoryEntry(
            timestampUtc: DateTime.parse(item['timestamp'] as String),
            text: item['text'] as String,
          ),
        )
        .toList();
    expect(
      actual.history,
      equals(expectedHistory),
      reason: 'history mismatch for $taskId in $caseId',
    );

    final subtasksJson = expected['subtasks'] as Map<String, Object?>?;
    if (subtasksJson == null) {
      expect(actual.subtasks, isEmpty);
    } else {
      expect(actual.subtasksAutoFinish, equals(subtasksJson['autoFinish']));
      final expectedSteps = (subtasksJson['steps'] as List<Object?>)
          .map((item) => item as Map<String, Object?>)
          .map(
            (item) => SubtaskItem(
              title: item['text'] as String,
              isCompleted: item['done'] as bool,
            ),
          )
          .toList();
      expect(actual.subtasks, equals(expectedSteps));
    }
  }
}

void main() {
  const tdfService = TdfService();
  final fixedDate = DateTime.utc(2026, 11, 10, 12, 0);

  group('TDF 0.7.0 Conformance Suite (spec/conformance/v0.7.0)', () {
    test('passes all parse_valid fixtures, canonical serialization, canonicalSourceDigest, and dueLeadEvaluation checks', () {
      const baseDir = 'spec/conformance/v0.7.0/parse_valid';
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

        _verifyNormalizedBoard(board, normalizedJson, id);

        if (normalizedJson['dueLeadEvaluation']
            case final Map<String, Object?> dueEval) {
          final evalTime = DateTime.parse(
            dueEval['evaluationTimeUtc'] as String,
          );
          final window = Duration(
            seconds: dueEval['dueLeadWindowSeconds'] as int,
          );
          final globalBoard = tdfService.parse(
            inputTdf,
            evaluationTime: evalTime,
            dueLeadWindow: window,
          );
          final globalExpected = dueEval['globalView'] as Map<String, Object?>;
          expect(
            globalBoard.focus.map((task) => task.id).toList(),
            equals(globalExpected['focus']),
            reason: 'Global Focus mismatch for $id',
          );
          expect(
            globalBoard.ready.map((task) => task.id).toList(),
            equals(globalExpected['ready']),
            reason: 'Global Ready mismatch for $id',
          );
          expect(
            globalBoard.planned.map((task) => task.id).toList(),
            equals(globalExpected['planned']),
            reason: 'Global Planned mismatch for $id',
          );
          expect(
            globalBoard.blocked.map((task) => task.id).toList(),
            equals(globalExpected['blocked']),
            reason: 'Global Blocked mismatch for $id',
          );
          expect(
            globalBoard.someday.map((task) => task.id).toList(),
            equals(globalExpected['someday']),
            reason: 'Global Someday mismatch for $id',
          );
          expect(
            globalBoard.completed.map((task) => task.id).toList(),
            equals(globalExpected['completed']),
            reason: 'Global Completed mismatch for $id',
          );

          final scopedExpected =
              dueEval['scopedLabelView'] as Map<String, Object?>;
          final scopedBoard = globalBoard.evaluateForContext(
            activeLabelId: scopedExpected['activeLabelId'] as String,
            evaluationTime: evalTime,
            dueLeadWindow: window,
          );
          expect(
            scopedBoard.focus.map((task) => task.id).toList(),
            equals(scopedExpected['focus']),
            reason: 'Scoped Focus mismatch for $id',
          );
          expect(
            scopedBoard.ready.map((task) => task.id).toList(),
            equals(scopedExpected['ready']),
            reason: 'Scoped Ready mismatch for $id',
          );
          expect(
            scopedBoard.planned.map((task) => task.id).toList(),
            equals(scopedExpected['planned']),
            reason: 'Scoped Planned mismatch for $id',
          );
          expect(
            scopedBoard.blocked.map((task) => task.id).toList(),
            equals(scopedExpected['blocked']),
            reason: 'Scoped Blocked mismatch for $id',
          );
          expect(
            scopedBoard.someday.map((task) => task.id).toList(),
            equals(scopedExpected['someday']),
            reason: 'Scoped Someday mismatch for $id',
          );
          expect(
            scopedBoard.completed.map((task) => task.id).toList(),
            equals(scopedExpected['completed']),
            reason: 'Scoped Completed mismatch for $id',
          );
        }
      }
    });

    test('passes all 46 parse_invalid fixtures with exact TdfErrorKind and line number', () {
      const baseDir = 'spec/conformance/v0.7.0/parse_invalid';
      final manifest = jsonDecode(
        File('$baseDir/manifest.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final cases = manifest['cases'] as List<Object?>;
      expect(cases.length, equals(46));

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

    test('passes all 20 bounds fixtures', () {
      const baseDir = 'spec/conformance/v0.7.0/bounds';
      final manifest = jsonDecode(
        File('$baseDir/manifest.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final cases = manifest['cases'] as List<Object?>;
      expect(cases.length, equals(20));

      for (final rawCase in cases) {
        final testCase = rawCase as Map<String, Object?>;
        final file = testCase['file'] as String;
        final isValid = testCase['valid'] as bool;
        final expectedError = testCase['expectedError'] as String?;
        final inputTdf = File('$baseDir/$file').readAsStringSync();

        if (isValid) {
          late TaskBoard board;
          expect(
            () {
              board = tdfService.parse(inputTdf, evaluationTime: fixedDate);
            },
            returnsNormally,
            reason: 'Valid bounds fixture $file must be accepted',
          );
          expect(
            () => tdfService.serialize(board),
            returnsNormally,
            reason:
                'Valid bounds fixture $file must serialize cleanly under 0.7.0 bounds',
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

    test('passes all 3 migration fixtures for 0.6.0 -> 0.7.0 and chained 0.5.0 -> 0.7.0', () {
      const baseDir = 'spec/conformance/v0.7.0/migration';
      final manifest = jsonDecode(
        File('$baseDir/manifest.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final cases = manifest['cases'] as List<Object?>;
      expect(cases.length, equals(3));

      for (final rawCase in cases) {
        final testCase = rawCase as Map<String, Object?>;
        final id = testCase['id'] as String;
        final inputFile = testCase['inputFile'] as String;
        final isValid = testCase['valid'] as bool;
        final sourceTimeZoneName = testCase['sourceTimeZone'] as String?;
        final tz = sourceTimeZoneName == 'Europe/Berlin'
            ? TdfTimeZoneContext.europeBerlin
            : null;
        final inputTdf = File('$baseDir/$inputFile').readAsStringSync();

        if (isValid) {
          final expectedFile = testCase['expectedFile'] as String;
          final expectedTdf = File('$baseDir/$expectedFile').readAsStringSync();

          final imported = TdfImporter.importDocument(
            inputTdf,
            sourceTimeZone: tz,
            evaluationTime: fixedDate,
          );
          expect(
            imported.migratedTdfContent,
            equals(expectedTdf),
            reason: 'Explicit TdfImporter.importDocument mismatch for $id',
          );

          if (testCase['sourceVersion'] == '0.6.0') {
            final stepMigrated = TdfImporter.migrate060To070(
              inputTdf,
              sourceTimeZone: tz,
            );
            expect(
              stepMigrated,
              equals(expectedTdf),
              reason: 'TdfImporter.migrate060To070 mismatch for $id',
            );
          }

          final loadedBoard = tdfService.parse(
            inputTdf,
            timeZone: tz,
            evaluationTime: fixedDate,
          );
          if (testCase['loadTimePreservesRawBlockedOn3cDeFgHiJ3']
              case final List<Object?> expectedBlocked) {
            final task3c = loadedBoard.findTask('3cDeFgHiJ3');
            expect(task3c, isNotNull);
            expect(
              task3c?.blockedByTaskIds,
              equals(expectedBlocked),
              reason:
                  'Read-only load-time conversion must preserve raw blocked entries untouched for $id',
            );
            final expectedBoard = tdfService.parse(
              expectedTdf,
              evaluationTime: fixedDate,
            );
            for (final expectedTask in expectedBoard.allTasks) {
              if (expectedTask.id == '3cDeFgHiJ3') continue;
              expect(
                loadedBoard.findTask(expectedTask.id)?.repeatRule,
                equals(expectedTask.repeatRule),
                reason:
                    'Load-time repeatRule extraction must match migrated repeatRule for ${expectedTask.id}',
              );
            }
          } else {
            expect(
              tdfService.serialize(loadedBoard),
              equals(expectedTdf),
              reason: 'Load-time conversion mismatch for $id',
            );
          }
        } else {
          final expectedEntityId = testCase['entityId'] as String;
          final expectedSuspendedLine = testCase['suspendedLine'] as int;
          final contextMatcher = isA<TdfContextException>()
              .having(
                (error) => error.kind,
                'kind',
                TdfContextOutcomeKind.importContextRequired,
              )
              .having((error) => error.entityId, 'entityId', expectedEntityId)
              .having((error) => error.line, 'line', expectedSuspendedLine);

          expect(
            () => tdfService.parse(inputTdf, evaluationTime: fixedDate),
            throwsA(contextMatcher),
            reason:
                'Invalid migration fixture $id must throw ImportContextRequired on parse',
          );
          expect(
            () => TdfImporter.migrate060To070(inputTdf),
            throwsA(contextMatcher),
            reason:
                'Invalid migration fixture $id must throw ImportContextRequired on migrate060To070',
          );
          expect(
            () =>
                TdfImporter.importDocument(inputTdf, evaluationTime: fixedDate),
            throwsA(contextMatcher),
            reason:
                'Invalid migration fixture $id must throw ImportContextRequired on importDocument',
          );
        }
      }
    });

    test('passes all timezone Mode 2 repeat lead, due lead evaluation, and downgradeTask vectors', () {
      const baseDir = 'spec/conformance/v0.7.0/timezone';
      final manifest = jsonDecode(
        File('$baseDir/vectors.json').readAsStringSync(),
      ) as Map<String, Object?>;
      const tz = TdfTimeZoneContext.europeBerlin;

      final repeatVectors = manifest['mode2RepeatLeadVectors'] as List<Object?>;
      expect(repeatVectors.length, equals(4));
      for (final rawVec in repeatVectors) {
        final vec = rawVec as Map<String, Object?>;
        final id = vec['id'] as String;
        final repeatMap = vec['repeat'] as Map<String, Object?>;
        final clockStr = repeatMap['clock'] as String;
        final rule = TaskRepeatRule(
          count: repeatMap['count'] as int,
          unit: _parseRepeatUnit(repeatMap['unit'] as String),
          clock: TdfRepeatClock.tryParse(clockStr) ?? TdfRepeatClock.midnight,
          leadDays: repeatMap['leadDays'] as int,
        );
        expect(
          'repeat ${rule.toTdfDirectiveArgs()}',
          equals(repeatMap['canonical']),
          reason: 'Canonical repeat directive mismatch for $id',
        );

        final completionUtc = _parseSpecDateTime(
          vec['completionInstantUtc'] as String,
        );
        final prevDueUtc = _parseSpecDateTime(vec['previousDueUtc'] as String);
        final prevSuspStr = vec['previousSuspendedUtc'] as String?;
        final prevSuspUtc = prevSuspStr != null
            ? _parseSpecDateTime(prevSuspStr)
            : null;

        final occurrence = rule.nextScheduleAnchoredOccurrence(
          completedAtUtc: completionUtc,
          oldDueUtc: prevDueUtc,
          timeZone: tz,
        );
        expect(
          occurrence.stepsK,
          equals(vec['advancementStepsK']),
          reason: 'stepsK mismatch for $id',
        );
        expect(
          occurrence.newDueUtc,
          equals(_parseSpecDateTime(vec['expectedNewDueUtc'] as String)),
          reason: 'expectedNewDueUtc mismatch for $id',
        );
        expect(
          occurrence.newSuspendedUtc,
          equals(_parseSpecDateTime(vec['computedNewSuspendedUtc'] as String)),
          reason: 'computedNewSuspendedUtc mismatch for $id',
        );

        final initialTask = TaskItem(
          id: '8jKaCdOkD2',
          title: 'Recurring Mode 2 Task',
          createdAt: DateTime.utc(2026, 1, 1, 8, 0),
          repeatRule: rule,
          dueAt: prevDueUtc,
          isDuePassive: vec['previousDuePassive'] as bool,
          dueNote: vec['previousDueNote'] as String?,
          suspendedAt: prevSuspUtc,
          suspendedNote: vec['previousSuspendedNote'] as String?,
        );
        final board = TaskBoard.evaluate(
          tasks: [initialTask],
          evaluationTime: completionUtc,
          timeZone: tz,
          queueBlock: TdfQueueBlock(
            modifiedAt: DateTime.utc(2026, 1, 1, 8, 0),
            taskIds: const ['8jKaCdOkD2'],
          ),
        );
        final afterComplete = board.completeTask(
          '8jKaCdOkD2',
          currentDate: completionUtc,
          timeZone: tz,
        );
        final updated = afterComplete.findTask('8jKaCdOkD2');
        expect(updated, isNotNull, reason: 'Task must remain live for $id');
        final expectedSuspStr = vec['expectedTaskSuspendedUtc'] as String?;
        expect(
          updated?.dueAt,
          equals(_parseSpecDateTime(vec['expectedNewDueUtc'] as String)),
          reason: 'Post-completion dueAt mismatch for $id',
        );
        expect(
          updated?.suspendedAt,
          equals(
            expectedSuspStr != null
                ? _parseSpecDateTime(expectedSuspStr)
                : null,
          ),
          reason: 'Post-completion suspendedAt mismatch for $id',
        );
        expect(
          updated?.isDuePassive,
          equals(vec['expectedDuePassive']),
          reason: 'Post-completion isDuePassive mismatch for $id',
        );
        expect(
          updated?.dueNote,
          equals(vec['expectedDueNote']),
          reason: 'Post-completion dueNote mismatch for $id',
        );
        expect(
          updated?.suspendedNote,
          equals(vec['expectedSuspendedNote']),
          reason: 'Post-completion suspendedNote mismatch for $id',
        );
      }

      final dueEvalVectors =
          manifest['dueLeadEvaluationVectors'] as List<Object?>;
      expect(dueEvalVectors.length, equals(5));
      for (final rawVec in dueEvalVectors) {
        final vec = rawVec as Map<String, Object?>;
        final id = vec['id'] as String;
        final nowUtc = _parseSpecDateTime(vec['nowUtc'] as String);
        final windowSec = vec['dueLeadWindowSeconds'] as int?;
        final window = windowSec != null ? Duration(seconds: windowSec) : null;
        final task = TaskItem(
          id: '1aEvalOkD2',
          title: 'Eval Task',
          createdAt: DateTime.utc(2026, 11, 1, 8, 0),
          isPriority: vec['isPriority'] as bool,
          dueAt: _parseSpecDateTime(vec['dueUtc'] as String),
          isDuePassive: vec['isDuePassive'] as bool,
        );
        expect(
          task.isWithinDueLeadWindow(nowUtc, window),
          equals(vec['expectedIsDueUrgent']),
          reason: 'isWithinDueLeadWindow mismatch for $id',
        );

        final regularTasks = [
          for (var i = 1; i <= 3; i++)
            TaskItem(
              id: '00000${i}OkD2',
              title: 'Regular $i',
              createdAt: DateTime.utc(2026, 11, 1, 8, i),
            ),
        ];
        final evaluated = TaskBoard.evaluate(
          tasks: [...regularTasks, task],
          evaluationTime: nowUtc,
          dueLeadWindow: window,
          queueBlock: TdfQueueBlock(
            modifiedAt: DateTime.utc(2026, 11, 1, 9, 0),
            taskIds: [...regularTasks.map((regular) => regular.id), task.id],
          ),
        );
        final inFocus = evaluated.focus.any((item) => item.id == task.id);
        expect(
          inFocus,
          equals(vec['expectedHasEffectivePriority']),
          reason: 'expectedHasEffectivePriority mismatch for $id',
        );
      }

      final downgradeVectors =
          manifest['downgradeTaskVectors'] as List<Object?>;
      expect(downgradeVectors.length, equals(3));
      for (final rawVec in downgradeVectors) {
        final vec = rawVec as Map<String, Object?>;
        final id = vec['id'] as String;
        final nowUtc = _parseSpecDateTime(vec['nowUtc'] as String);
        final window = Duration(seconds: vec['dueLeadWindowSeconds'] as int);
        final targetId = vec['targetTaskId'] as String;
        final queueBefore = (vec['queueBefore'] as List<Object?>)
            .cast<String>();
        final targetBefore = vec['targetBefore'] as Map<String, Object?>;
        final baseCreated = DateTime.utc(2026, 11, 1, 8, 0);

        final tasks = <TaskItem>[
          for (final taskId in queueBefore)
            if (taskId == targetId)
              TaskItem(
                id: taskId,
                title: 'Target $taskId',
                createdAt: baseCreated,
                modifiedAt: baseCreated,
                isPriority: targetBefore['priority'] as bool,
                dueAt: _parseSpecDateTime(targetBefore['dueUtc'] as String),
                isDuePassive: targetBefore['isDuePassive'] as bool,
                dueNote: targetBefore['dueNote'] as String?,
              )
            else
              TaskItem(
                id: taskId,
                title: 'Other $taskId',
                createdAt: baseCreated,
                modifiedAt: baseCreated,
                isPriority: taskId.contains('Urgent'),
              ),
        ];

        final beforeBoard = TaskBoard.evaluate(
          tasks: tasks,
          evaluationTime: nowUtc,
          dueLeadWindow: window,
          queueBlock: TdfQueueBlock(
            modifiedAt: baseCreated,
            taskIds: queueBefore,
          ),
        );
        final afterBoard = beforeBoard.downgradeTask(
          targetId,
          currentDate: nowUtc,
          dueLeadWindow: window,
        );
        expect(
          afterBoard.queueBlock.taskIds,
          equals(vec['expectedQueueAfter']),
          reason: 'expectedQueueAfter mismatch for $id',
        );

        final expectedAfter =
            vec['expectedTargetAfter'] as Map<String, Object?>;
        final updatedTarget = afterBoard.findTask(targetId);
        expect(updatedTarget, isNotNull);
        expect(
          updatedTarget?.isPriority,
          equals(expectedAfter['priority']),
          reason: 'priority after downgrade mismatch for $id',
        );
        expect(
          updatedTarget?.dueAt,
          equals(_parseSpecDateTime(expectedAfter['dueUtc'] as String)),
          reason: 'dueAt after downgrade mismatch for $id',
        );
        expect(
          updatedTarget?.isDuePassive,
          equals(expectedAfter['isDuePassive']),
          reason: 'isDuePassive after downgrade mismatch for $id',
        );
        expect(
          updatedTarget?.dueNote,
          equals(expectedAfter['dueNote']),
          reason: 'dueNote after downgrade mismatch for $id',
        );
        final expectedTierName = expectedAfter['derivedTier'] as String;
        final actualTier = afterBoard.findTierOfTask(targetId);
        expect(
          actualTier?.name.toLowerCase(),
          equals(expectedTierName.toLowerCase()),
          reason: 'derivedTier after downgrade mismatch for $id',
        );
        expect(
          updatedTarget?.effectiveModifiedAt.isAfter(baseCreated),
          equals(expectedAfter['modifiedAdvanced']),
          reason: 'modifiedAdvanced mismatch for $id',
        );
      }
    });
  });
}
