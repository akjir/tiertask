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

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/models/app_workspace.dart';
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_board_sync.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/services/tdf_service.dart';

void main() {
  final baseInstant = DateTime.utc(2026, 11, 4, 12, 0, 0);
  DateTime t(int seconds) => baseInstant.add(Duration(seconds: seconds));

  group('TDF 0.5.0 Section 6.7.9 Three-Way Merge Verification Table', () {
    const taskId = '8jKaCdOkD2';
    final created = DateTime.utc(2026, 11, 1, 8, 0, 0);

    TaskBoard singleTaskBoard({
      required String name,
      required String? note,
      DateTime? modifiedAt,
    }) {
      final task = TaskItem(
        id: taskId,
        title: name,
        note: note,
        createdAt: created,
        modifiedAt: modifiedAt,
      );
      return TaskBoard.evaluate(tasks: [task], evaluationTime: t(100));
    }

    final baseline = singleTaskBoard(name: 'N0', note: 'Q0', modifiedAt: t(10));

    test('executes all 6 scalar verification table cases symmetrically in both (L, R) and (R, L) directions', () {
      final cases =
          <
            ({
              String description,
              TaskBoard local,
              TaskBoard incoming,
              String expectedName,
              String expectedNote,
              DateTime expectedRevision,
            })
          >[
            (
              description: 'Independent edits',
              local: singleTaskBoard(name: 'N1', note: 'Q0', modifiedAt: t(11)),
              incoming: singleTaskBoard(
                name: 'N0',
                note: 'Q1',
                modifiedAt: t(12),
              ),
              expectedName: 'N1',
              expectedNote: 'Q1',
              expectedRevision: t(13),
            ),
            (
              description: 'Matching edits',
              local: singleTaskBoard(name: 'N1', note: 'Q0', modifiedAt: t(11)),
              incoming: singleTaskBoard(
                name: 'N1',
                note: 'Q0',
                modifiedAt: t(12),
              ),
              expectedName: 'N1',
              expectedNote: 'Q0',
              expectedRevision: t(12),
            ),
            (
              description: 'Same field conflict',
              local: singleTaskBoard(name: 'N1', note: 'Q0', modifiedAt: t(11)),
              incoming: singleTaskBoard(
                name: 'N2',
                note: 'Q0',
                modifiedAt: t(12),
              ),
              expectedName: 'N2',
              expectedNote: 'Q0',
              expectedRevision: t(12),
            ),
            (
              description: 'Equal timestamp conflict',
              local: singleTaskBoard(
                name: 'Alpha',
                note: 'Q0',
                modifiedAt: t(12),
              ),
              incoming: singleTaskBoard(
                name: 'Zulu',
                note: 'Q0',
                modifiedAt: t(12),
              ),
              expectedName: 'Zulu',
              expectedNote: 'Q0',
              expectedRevision: t(12),
            ),
            (
              description: 'Conflict and independent edit',
              local: singleTaskBoard(
                name: 'N1',
                note: 'Alpha',
                modifiedAt: t(11),
              ),
              incoming: singleTaskBoard(
                name: 'N0',
                note: 'Zulu',
                modifiedAt: t(12),
              ),
              expectedName: 'N1',
              expectedNote: 'Zulu',
              expectedRevision: t(13),
            ),
            (
              description: 'Unstamped external edit',
              local: singleTaskBoard(name: 'N0', note: 'Q0', modifiedAt: t(20)),
              incoming: singleTaskBoard(
                name: 'N1',
                note: 'Q0',
                modifiedAt: t(10),
              ),
              expectedName: 'N1',
              expectedNote: 'Q0',
              expectedRevision: t(21),
            ),
          ];

      for (final testCase in cases) {
        final forward = TaskBoardSync.merge(
          primary: testCase.local,
          secondary: testCase.incoming,
          baseline: baseline,
          evaluationTime: t(500),
        );
        final reversed = TaskBoardSync.merge(
          primary: testCase.incoming,
          secondary: testCase.local,
          baseline: baseline,
          evaluationTime: t(500),
        );

        final forwardTask = forward.findTask(taskId)!;
        final reversedTask = reversed.findTask(taskId)!;

        expect(
          forwardTask.title,
          equals(testCase.expectedName),
          reason: '${testCase.description} (forward): name mismatch',
        );
        expect(
          forwardTask.note,
          equals(testCase.expectedNote),
          reason: '${testCase.description} (forward): note mismatch',
        );
        expect(
          forwardTask.modifiedAt,
          equals(testCase.expectedRevision),
          reason: '${testCase.description} (forward): revision mismatch',
        );

        expect(
          reversedTask.title,
          equals(testCase.expectedName),
          reason: '${testCase.description} (reversed): name mismatch',
        );
        expect(
          reversedTask.note,
          equals(testCase.expectedNote),
          reason: '${testCase.description} (reversed): note mismatch',
        );
        expect(
          reversedTask.modifiedAt,
          equals(testCase.expectedRevision),
          reason: '${testCase.description} (reversed): revision mismatch',
        );
      }

      // Without a known common baseline, the independent-edits case MUST retain the complete version at T12:
      final noBaselineForward = TaskBoardSync.merge(
        primary: singleTaskBoard(name: 'N1', note: 'Q0', modifiedAt: t(11)),
        secondary: singleTaskBoard(name: 'N0', note: 'Q1', modifiedAt: t(12)),
        evaluationTime: t(500),
      );
      final noBaselineReversed = TaskBoardSync.merge(
        primary: singleTaskBoard(name: 'N0', note: 'Q1', modifiedAt: t(12)),
        secondary: singleTaskBoard(name: 'N1', note: 'Q0', modifiedAt: t(11)),
        evaluationTime: t(500),
      );
      for (final board in [noBaselineForward, noBaselineReversed]) {
        final winner = board.findTask(taskId)!;
        expect(winner.title, equals('N0'));
        expect(winner.note, equals('Q1'));
        expect(winner.modifiedAt, equals(t(12)));
      }
    });

    test('combines independent label additions and removals, preserves atomic task occurrence state by completion counter, compares UTF-8 supplementary characters, and preserves revisions on idempotent re-merge', () {
      const l1 = '000001OkD2';
      const l2 = '000002OkD2';
      const l3 = '000003OkD2';
      final labels = <TdfLabel>[
        const TdfLabel(id: l1, name: 'L1'),
        const TdfLabel(id: l2, name: 'L2'),
        const TdfLabel(id: l3, name: 'L3'),
      ];

      // Baseline has labels {l1, l2}, completions = 1, repeat 1 days:
      final baseTask = TaskItem(
        id: taskId,
        title: 'Recurring Task',
        createdAt: created,
        queuedAt: t(0),
        modifiedAt: t(10),
        completions: 1,
        labelIds: const [l1, l2],
        repeatRule: const TaskRepeatRule(count: 1, unit: RepeatUnit.days),
      );
      final baseBoard = TaskBoard.evaluate(
        tasks: [baseTask],
        labels: labels,
        evaluationTime: t(100),
      );

      // Local removes l1 and completes occurrence 2 (completions = 2) at T11:
      final localTask = baseTask.copyWith(
        labelIds: const [l2],
        completions: 2,
        queuedAt: t(86400),
        suspendedAt: t(86400),
        modifiedAt: t(11),
      );
      final localBoard = TaskBoard.evaluate(
        tasks: [localTask],
        labels: labels,
        evaluationTime: t(100),
      );

      // Remote adds l3 and edits subtasks/deferral on older occurrence 1 (completions = 1) at later timestamp T15:
      final remoteTask = baseTask.copyWith(
        labelIds: const [l1, l2, l3],
        completions: 1,
        suspendedAt: t(3600),
        modifiedAt: t(15),
      );
      final remoteBoard = TaskBoard.evaluate(
        tasks: [remoteTask],
        labels: labels,
        evaluationTime: t(100),
      );

      final merged = TaskBoardSync.merge(
        primary: localBoard,
        secondary: remoteBoard,
        baseline: baseBoard,
        evaluationTime: t(100),
      );
      final mergedTask = merged.findTask(taskId)!;

      // Label set merge: B = {l1, l2}, L = {l2} (removed l1), R = {l1, l2, l3} (added l3) -> {l2, l3}:
      expect(
        mergedTask.labelIds,
        equals([l2, l3]),
        reason: 'Label set must combine independent removal of l1 and addition of l3',
      );
      // Occurrence state: L has completions = 2 > R.completions = 1, so L is the complete winner W even though R has later T15:
      expect(
        mergedTask.completions,
        equals(2),
        reason: 'Greater completion counter (2 > 1) must win over later timestamp on older occurrence',
      );
      expect(mergedTask.suspendedAt, equals(t(86400)));
      expect(mergedTask.modifiedAt, equals(t(16)));

      // Merging the same result again must preserve revisions:
      final remerged = TaskBoardSync.merge(
        primary: merged,
        secondary: merged,
        baseline: merged,
        evaluationTime: t(200),
      );
      expect(remerged.findTask(taskId)!.modifiedAt, equals(t(16)));

      // UTF-8 byte order vs UTF-16 code-unit order for supplementary character above U+FFFF:
      // U+FF21 (FULLWIDTH LATIN CAPITAL LETTER A, 'Ａ') has UTF-16 [0xFF21] and UTF-8 [0xEF, 0xBC, 0xA1].
      // U+1F680 (ROCKET, '🚀') has UTF-16 [0xD83D, 0xDE80] and UTF-8 [0xF0, 0x9F, 0x9A, 0x80].
      // In UTF-16 code units, 0xD83D < 0xFF21, so '🚀' < 'Ａ'.
      // In unsigned UTF-8 bytes, 0xF0 > 0xEF, so '🚀' > 'Ａ'!
      final bmpFullwidthBoard = singleTaskBoard(
        name: '\uFF21',
        note: null,
        modifiedAt: t(12),
      );
      final supplementaryRocketBoard = singleTaskBoard(
        name: '🚀',
        note: null,
        modifiedAt: t(12),
      );
      final utf8Winner = TaskBoardSync.merge(
        primary: bmpFullwidthBoard,
        secondary: supplementaryRocketBoard,
        evaluationTime: t(100),
      );
      expect(
        utf8Winner.findTask(taskId)!.title,
        equals('🚀'),
        reason: 'UTF-8 byte comparison must rank U+1F680 (0xF0...) above U+FF21 (0xEF...)',
      );
    });

    test('produces identical merge results for equivalent quoting, escaping, decimal GPS strings, and inline vs block condition syntax, and rejects merged dependency cycles', () {
      const parser = TdfService();
      const docA = '''
tdf 0.5.0

label 000001OkD2 {
    name 'Work & Ops'
    condition location 048.13715400 -000.000 0250.00
}
''';
      const docB = '''
tdf 0.5.0

label 000001OkD2 {
    name "Work & Ops"
    condition {
        location 48.137154 0 250
    }
}
''';
      final boardA = parser.parse(docA, evaluationTime: t(100));
      final boardB = parser.parse(docB, evaluationTime: t(100));

      final merged = TaskBoardSync.merge(
        primary: boardA,
        secondary: boardB,
        baseline: boardA,
        evaluationTime: t(100),
      );
      expect(
        merged.labels.single.modifiedAt,
        isNull,
        reason: 'Equivalent decoded payloads with omitted modified must not advance revision',
      );

      // Merged dependency cycle from two individually acyclic inputs:
      const idA = '00000AOkD2';
      const idB = '00000BOkD2';
      final leftA = TaskItem(
        id: idA,
        title: 'A blocked by B on Left',
        createdAt: created,
        modifiedAt: t(20),
        dependencies: const [TdfTaskDependency(taskId: idB)],
      );
      final leftB = TaskItem(
        id: idB,
        title: 'B unblocked on Left',
        createdAt: created,
        modifiedAt: t(10),
      );
      final rightA = TaskItem(
        id: idA,
        title: 'A unblocked on Right',
        createdAt: created,
        modifiedAt: t(10),
      );
      final rightB = TaskItem(
        id: idB,
        title: 'B blocked by A on Right',
        createdAt: created,
        modifiedAt: t(20),
        dependencies: const [TdfTaskDependency(taskId: idA)],
      );

      final leftBoard = TaskBoard.evaluate(
        tasks: [leftA, leftB],
        evaluationTime: t(100),
      );
      final rightBoard = TaskBoard.evaluate(
        tasks: [rightA, rightB],
        evaluationTime: t(100),
      );

      expect(
        () => TaskBoardSync.merge(
          primary: leftBoard,
          secondary: rightBoard,
          evaluationTime: t(100),
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.circularDependency,
          ),
        ),
        reason: 'Combined dependency cycle A -> B -> A must fail validation with CircularDependency',
      );
    });
  });

  group(
    'TDF 0.5.0 Section 6.8 & 6.8.5 Deletion Records, Generations & Recovery',
    () {
      const taskId = '8jKaCdOkD2';
      const task2Id = '3nQp7ROkB8';
      const labelId = 'work00OkD2';
      final created = DateTime.utc(2026, 10, 1, 8, 0, 0);

      test('enforces exact 30-day (2,592,000s) deletion record expiry, single generation increment across multiple expiries, and nonzero generation retention', () {
        final delTime = DateTime.utc(2026, 10, 5, 12, 0, 0);
        final exactly30Days = delTime.add(const Duration(seconds: 2592000));
        final over30Days = delTime.add(const Duration(seconds: 2592001));

        final boardWithRecords = TaskBoard.evaluate(
          tasks: const [],
          deletedBlock: TdfDeletedBlock(
            generation: 0,
            tasks: [
              TdfDeletedTaskRecord(
                taskId: taskId,
                deletedAt: delTime,
                completionsCheckpoint: 4,
              ),
            ],
            labels: [
              TdfDeletedLabelRecord(labelId: labelId, deletedAt: delTime),
            ],
          ),
          evaluationTime: exactly30Days,
        );

        // At exactly 30 days (2,592,000s), records are kept and generation stays 0:
        final mergedAt30Days = TaskBoardSync.merge(
          primary: boardWithRecords,
          secondary: boardWithRecords,
          baseline: boardWithRecords,
          evaluationTime: exactly30Days,
        );
        expect(mergedAt30Days.deletedBlock.generation, equals(0));
        expect(mergedAt30Days.deletedBlock.totalRecords, equals(2));

        // At 2,592,001s (> 30 days), both records expire and generation increments once from 0 -> 1:
        final mergedOver30Days = TaskBoardSync.merge(
          primary: boardWithRecords,
          secondary: boardWithRecords,
          baseline: boardWithRecords,
          evaluationTime: over30Days,
        );
        expect(
          mergedOver30Days.deletedBlock.generation,
          equals(1),
          reason: 'Expiring multiple records in one cleanup must increment generation once',
        );
        expect(mergedOver30Days.deletedBlock.totalRecords, equals(0));
        expect(
          mergedOver30Days.deletedBlock.isDefaultEmpty,
          isFalse,
          reason: 'Nonzero generation must keep deleted block non-default',
        );
      });

      test('handles DeletionConflict, Delete and Undelete resolutions with completion checkpoint preservation, and single generation increment when combined with cleanup', () {
        final baseTask = TaskItem(
          id: taskId,
          title: 'Original Task',
          createdAt: created,
          queuedAt: t(0),
          modifiedAt: t(10),
          completions: 3,
          labelIds: const [labelId],
        );
        const baseLabel = TdfLabel(id: labelId, name: 'Work');
        final baseline = TaskBoard.evaluate(
          tasks: [baseTask],
          labels: const [baseLabel],
          evaluationTime: t(10),
        );

        // Local edits the task (completions = 5, new title) at T15:
        final editedTask = baseTask.copyWith(
          title: 'Edited Task',
          completions: 5,
          modifiedAt: t(15),
        );
        final localBoard = TaskBoard.evaluate(
          tasks: [editedTask],
          labels: const [baseLabel],
          evaluationTime: t(15),
        );

        // Remote deleted the task at T20 with checkpoint 7 (e.g., completed twice more before deletion):
        final remoteBoard = TaskBoard.evaluate(
          tasks: const [],
          labels: const [baseLabel],
          deletedBlock: TdfDeletedBlock(
            generation: 0,
            tasks: [
              TdfDeletedTaskRecord(
                taskId: taskId,
                deletedAt: t(20),
                completionsCheckpoint: 7,
              ),
            ],
          ),
          evaluationTime: t(20),
        );

        // Without user resolution, merge must return DeletionConflict in both directions:
        for (final pair in [
          (localBoard, remoteBoard),
          (remoteBoard, localBoard),
        ]) {
          expect(
            () => TaskBoardSync.merge(
              primary: pair.$1,
              secondary: pair.$2,
              baseline: baseline,
              evaluationTime: t(30),
            ),
            throwsA(
              isA<TdfSyncOutcomeException>()
                  .having(
                    (error) => error.kind,
                    'kind',
                    TdfSyncOutcomeKind.deletionConflict,
                  )
                  .having(
                    (error) => error.conflictedTaskIds,
                    'conflictedTaskIds',
                    contains(taskId),
                  ),
            ),
          );
        }

        // Resolution = Delete at T30: decisionRevision = max(T30, T20 + 1s) = T30, checkpoint = max(5, 3, 7) = 7, generation stays 0:
        final resolvedDelete = TaskBoardSync.merge(
          primary: localBoard,
          secondary: remoteBoard,
          baseline: baseline,
          taskConflictResolutions: const {taskId: TdfDeletionResolution.delete},
          evaluationTime: t(30),
        );
        expect(resolvedDelete.findTask(taskId), isNull);
        expect(resolvedDelete.deletedBlock.generation, equals(0));
        final deleteRecord = resolvedDelete.deletedBlock.findTaskRecord(
          taskId,
        )!;
        expect(deleteRecord.deletedAt, equals(t(30)));
        expect(deleteRecord.completionsCheckpoint, equals(7));

        // Resolution = Undelete at T18 (earlier than T20): decisionRevision = max(T18, T20 + 1s) = T21,
        // restores edited task with completions = 7, removes record, and increments generation 0 -> 1:
        final resolvedUndelete = TaskBoardSync.merge(
          primary: localBoard,
          secondary: remoteBoard,
          baseline: baseline,
          taskConflictResolutions: const {
            taskId: TdfDeletionResolution.undelete,
          },
          evaluationTime: t(18),
        );
        final restoredTask = resolvedUndelete.findTask(taskId)!;
        expect(restoredTask.title, equals('Edited Task'));
        expect(restoredTask.completions, equals(7));
        expect(restoredTask.modifiedAt, equals(t(21)));
        expect(resolvedUndelete.deletedBlock.findTaskRecord(taskId), isNull);
        expect(resolvedUndelete.deletedBlock.generation, equals(1));
        expect(resolvedUndelete.queueBlock.taskIds, contains(taskId));
      });

      test('detects SyncGenerationRollback, RecoveryRequired on unacknowledged generation expiry or completion regression, and supports explicit new-ID recovery with reference rewriting', () {
        final sharedTask = TaskItem(
          id: taskId,
          title: 'Shared Task',
          createdAt: created,
          queuedAt: t(0),
          modifiedAt: t(10),
          completions: 4,
        );
        final baseline = TaskBoard.evaluate(
          tasks: [sharedTask],
          deletedBlock: TdfDeletedBlock(generation: 2),
          evaluationTime: t(10),
        );

        // 1. SyncGenerationRollback when incoming generation < acknowledged generation:
        final rolledBackRemote = TaskBoard.evaluate(
          tasks: [sharedTask],
          deletedBlock: TdfDeletedBlock(generation: 1),
          evaluationTime: t(20),
        );
        expect(
          () => TaskBoardSync.merge(
            primary: baseline,
            secondary: rolledBackRemote,
            baseline: baseline,
            acknowledgedGeneration: 2,
            evaluationTime: t(20),
          ),
          throwsA(
            isA<TdfSyncOutcomeException>().having(
              (error) => error.kind,
              'kind',
              TdfSyncOutcomeKind.syncGenerationRollback,
            ),
          ),
        );

        // 2. Completion counter regression below baseline (completions 3 < baseline 4) -> RecoveryRequired:
        final regressedLocal = TaskBoard.evaluate(
          tasks: [sharedTask.copyWith(completions: 3, modifiedAt: t(15))],
          deletedBlock: TdfDeletedBlock(generation: 2),
          evaluationTime: t(20),
        );
        expect(
          () => TaskBoardSync.merge(
            primary: regressedLocal,
            secondary: baseline,
            baseline: baseline,
            acknowledgedGeneration: 2,
            evaluationTime: t(20),
          ),
          throwsA(
            isA<TdfSyncOutcomeException>().having(
              (error) => error.kind,
              'kind',
              TdfSyncOutcomeKind.recoveryRequired,
            ),
          ),
        );

        // 3. Shared generation increased (2 -> 3): unchanged cached entity is discarded,
        // but local-only or locally edited entity absent remotely triggers RecoveryRequired:
        const ambLabelId = 'ambLabOkD2';
        const ambTask1Id = 'ambT01OkD2';
        const ambTask2Id = 'ambT02OkD2';
        const ambLabel = TdfLabel(id: ambLabelId, name: 'Ambiguous Label');
        final ambTask1 = TaskItem(
          id: ambTask1Id,
          title: 'Ambiguous Prerequisite',
          createdAt: created,
          queuedAt: t(11),
          modifiedAt: t(11),
          labelIds: const [ambLabelId],
        );
        final ambTask2 = TaskItem(
          id: ambTask2Id,
          title: 'Ambiguous Dependent',
          createdAt: created,
          queuedAt: t(12),
          modifiedAt: t(12),
          labelIds: const [ambLabelId],
          dependencies: const [
            TdfTaskDependency(taskId: ambTask1Id, requiredCompletion: 2),
          ],
        );

        final localWithAmbiguous = TaskBoard.evaluate(
          tasks: [sharedTask, ambTask1, ambTask2],
          labels: const [ambLabel],
          deletedBlock: TdfDeletedBlock(generation: 2),
          evaluationTime: t(20),
        );
        final advancedShared = TaskBoard.evaluate(
          tasks: const [], // sharedTask was deleted and its record expired in generation 3
          deletedBlock: TdfDeletedBlock(generation: 3),
          evaluationTime: t(20),
        );

        expect(
          () => TaskBoardSync.merge(
            primary: localWithAmbiguous,
            secondary: advancedShared,
            baseline: baseline,
            acknowledgedGeneration: 2,
            evaluationTime: t(20),
          ),
          throwsA(
            isA<TdfSyncOutcomeException>()
                .having(
                  (error) => error.kind,
                  'kind',
                  TdfSyncOutcomeKind.recoveryRequired,
                )
                .having(
                  (error) => error.ambiguousTaskIds,
                  'ambiguousTaskIds',
                  containsAll([ambTask1Id, ambTask2Id]),
                )
                .having(
                  (error) => error.ambiguousLabelIds,
                  'ambiguousLabelIds',
                  contains(ambLabelId),
                ),
          ),
        );

        // Explicit recovery generates new 10-character Base62 IDs, rewrites references between recovered entities,
        // and discards the unchanged cached sharedTask:
        final recoveredBoard = TaskBoardSync.recoverAmbiguousEntities(
          localBoard: localWithAmbiguous,
          sharedBoard: advancedShared,
          baseline: baseline,
          recoverTaskIds: const [ambTask1Id, ambTask2Id],
          recoverLabelIds: const [ambLabelId],
          evaluationTime: t(30),
        );

        expect(recoveredBoard.deletedBlock.generation, equals(3));
        expect(
          recoveredBoard.findTask(taskId),
          isNull,
          reason: 'Unchanged cached sharedTask absent from advancedShared must be discarded',
        );
        expect(recoveredBoard.labels.length, equals(1));
        final newLabelId = recoveredBoard.labels.single.id;
        expect(newLabelId, isNot(equals(ambLabelId)));
        expect(isValidLabelId(newLabelId), isTrue);

        expect(recoveredBoard.allTasks.length, equals(2));
        final recTask1 = recoveredBoard.allTasks.firstWhere(
          (task) => task.title == 'Ambiguous Prerequisite',
        );
        final recTask2 = recoveredBoard.allTasks.firstWhere(
          (task) => task.title == 'Ambiguous Dependent',
        );
        expect(recTask1.id, isNot(equals(ambTask1Id)));
        expect(recTask2.id, isNot(equals(ambTask2Id)));
        expect(recTask1.labelIds, equals([newLabelId]));
        expect(recTask2.labelIds, equals([newLabelId]));
        expect(
          recTask2.dependencies,
          equals([
            TdfTaskDependency(taskId: recTask1.id, requiredCompletion: 2),
          ]),
          reason: 'Recovered dependent must rewrite prerequisite ID to new recovered task ID while preserving requiredCompletion',
        );
      });

      test('creates a deletion record when a compatible baseline proves an external deletion without an existing record', () {
        final task1 = TaskItem(
          id: taskId,
          title: 'Task 1',
          createdAt: created,
          queuedAt: t(0),
          modifiedAt: t(10),
          completions: 2,
        );
        final task2 = TaskItem(
          id: task2Id,
          title: 'Task 2',
          createdAt: created,
          queuedAt: t(1),
          modifiedAt: t(10),
        );
        final baseline = TaskBoard.evaluate(
          tasks: [task1, task2],
          evaluationTime: t(10),
        );
        // External editor deleted task1 from secondary without writing a deleted record:
        final externallyDeletedBoard = TaskBoard.evaluate(
          tasks: [task2],
          evaluationTime: t(10),
        );

        final merged = TaskBoardSync.merge(
          primary: baseline,
          secondary: externallyDeletedBoard,
          baseline: baseline,
          evaluationTime: t(25),
        );
        expect(merged.findTask(taskId), isNull);
        final createdRecord = merged.deletedBlock.findTaskRecord(taskId);
        expect(createdRecord, isNotNull);
        expect(createdRecord!.deletedAt, equals(t(25)));
        expect(createdRecord.completionsCheckpoint, equals(2));
      });
    },
  );

  group('TDF 0.5.0 Section 6.11.2 Shared Queue Synchronization', () {
    const id1 = '000001OkD2';
    const id2 = '000002OkD2';
    const id3 = '000003OkD2';
    final created = DateTime.utc(2026, 11, 1, 8, 0, 0);

    test('merges shared queue order via three-way baseline rules, filters completed tasks, appends concurrent additions by ascending UTC queued then ASCII ID, and computes deterministic queue revision', () {
      final t1 = TaskItem(
        id: id1,
        title: 'Task 1',
        createdAt: created,
        queuedAt: t(1),
        modifiedAt: t(10),
      );
      final t2 = TaskItem(
        id: id2,
        title: 'Task 2',
        createdAt: created,
        queuedAt: t(2),
        modifiedAt: t(10),
      );
      final baseline = TaskBoard.evaluate(
        tasks: [t1, t2],
        queueBlock: TdfQueueBlock(modifiedAt: t(10), taskIds: const [id1, id2]),
        evaluationTime: t(10),
      );

      // Local reorders queue to [id2, id1] at T15:
      final localBoard = TaskBoard.evaluate(
        tasks: [t1, t2],
        queueBlock: TdfQueueBlock(modifiedAt: t(15), taskIds: const [id2, id1]),
        evaluationTime: t(15),
      );

      // Remote leaves [id1, id2] order unchanged from baseline, but adds t3 (queued at t(3)) at T18:
      final t3 = TaskItem(
        id: id3,
        title: 'Task 3 Added Remotely',
        createdAt: created,
        queuedAt: t(3),
        modifiedAt: t(18),
      );
      final remoteBoard = TaskBoard.evaluate(
        tasks: [t1, t2, t3],
        queueBlock: TdfQueueBlock(
          modifiedAt: t(18),
          taskIds: const [id1, id2, id3],
        ),
        evaluationTime: t(18),
      );

      // Both changed queue relative to baseline ([id2, id1] vs [id1, id2, id3]);
      // complete queue winner is remoteBoard (T18 > T15), preserving [id1, id2, id3] at T18:
      final mergedConflict = TaskBoardSync.merge(
        primary: localBoard,
        secondary: remoteBoard,
        baseline: baseline,
        evaluationTime: t(100),
      );
      expect(mergedConflict.queueBlock.taskIds, equals([id1, id2, id3]));
      expect(mergedConflict.queueBlock.modifiedAt, equals(t(18)));

      // When local has newer queue revision T20 ([id2, id1]) and remote added t3 at T18 ([id1, id2, id3]),
      // complete queue winner is local ([id2, id1]), and missing t3 is appended -> [id2, id1, id3] with revision max(T10, T20, T18) + 1s = T21:
      final localNewerQueue = TaskBoard.evaluate(
        tasks: [t1, t2],
        queueBlock: TdfQueueBlock(modifiedAt: t(20), taskIds: const [id2, id1]),
        evaluationTime: t(20),
      );
      final mergedForward = TaskBoardSync.merge(
        primary: localNewerQueue,
        secondary: remoteBoard,
        baseline: baseline,
        evaluationTime: t(100),
      );
      final mergedReversed = TaskBoardSync.merge(
        primary: remoteBoard,
        secondary: localNewerQueue,
        baseline: baseline,
        evaluationTime: t(100),
      );
      for (final board in [mergedForward, mergedReversed]) {
        expect(board.queueBlock.taskIds, equals([id2, id1, id3]));
        expect(
          board.queueBlock.modifiedAt,
          equals(t(21)),
          reason: 'Reconciled queue differing from winning input queue must advance to greatest observed queue revision + 1s without using wall clock',
        );
      }
    });
  });

  group(
    'WorkspaceSyncState Binary Serialization & SettingsRepository Persistence',
    () {
      test('round-trips WorkspaceSyncState binary encoding including acknowledged generations and persists per-workspace sync state', () async {
        final state = WorkspaceSyncState(
          lastSyncedLocalTdf: 'tdf 0.5.0\n\ntask 000001OkD2 {\n    name "Local"\n    created 2026-11-01 08:00\n}\n',
          lastSyncedRemoteTdf: 'tdf 0.5.0\n\ntask 000001OkD2 {\n    name "Remote"\n    created 2026-11-01 08:00\n}\n',
          deletedLabelTimestamps: <String, DateTime>{
            'work00OkD2': DateTime.utc(2026, 11, 2, 10, 15, 30),
            'home00OkD2': DateTime.utc(2026, 11, 2, 11, 0, 0),
          },
          acknowledgedLocalGeneration: 4,
          acknowledgedRemoteGeneration: 7,
        );

        final encoded = state.toBytes();
        final decoded = WorkspaceSyncState.fromBytes(encoded);
        expect(decoded, equals(state));
        expect(decoded.hashCode, equals(state.hashCode));
        expect(decoded.acknowledgedLocalGeneration, equals(4));
        expect(decoded.acknowledgedRemoteGeneration, equals(7));

        expect(
          WorkspaceSyncState.fromBytes(Uint8List(0)),
          equals(WorkspaceSyncState.empty),
        );

        final repository = InMemorySettingsRepository();
        expect(
          await repository.loadWorkspaceSyncState(AppWorkspace.defaultId),
          equals(WorkspaceSyncState.empty),
        );

        await repository.saveWorkspaceSyncState(AppWorkspace.defaultId, state);
        expect(
          await repository.loadWorkspaceSyncState(AppWorkspace.defaultId),
          equals(state),
        );
      });
    },
  );
}
