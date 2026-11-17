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
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_location.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_payload_comparison.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/tdf_timezone.dart';
import 'package:tiertask/models/workspace_sync_state.dart';
import 'package:tiertask/repositories/settings_repository.dart';
import 'package:tiertask/services/tdf_service.dart';

void main() {
  final baseInstant = DateTime.utc(2026, 11, 4, 12, 0, 0);
  final defaultCreated = DateTime.utc(2026, 11, 1, 8, 0, 0);
  DateTime t(int seconds) => baseInstant.add(Duration(seconds: seconds));
  TdfQueueBlock makeQueue(int seconds, List<String> taskIds) =>
      TdfQueueBlock(modifiedAt: t(seconds), taskIds: taskIds);

  TaskItem makeTask(
    String id,
    String title, [
    int modSec = 10,
    int comp = 0,
    List<String> labels = const [],
    List<TdfTaskDependency> deps = const [],
    String? note,
  ]) => TaskItem(
    id: id,
    title: title,
    note: note,
    createdAt: defaultCreated,
    modifiedAt: modSec < 0 ? null : t(modSec),
    completions: comp,
    labelIds: labels,
    dependencies: deps,
  );

  TaskBoard evalBoard(
    List<TaskItem> tasks, [
    TdfQueueBlock? queue,
    int atSec = 100,
    int? gen,
    List<TdfLabel> labels = const [],
    TdfDeletedBlock? deleted,
    DateTime? at,
  ]) => TaskBoard.evaluate(
    tasks: tasks,
    labels: labels,
    deletedBlock:
        deleted ?? (gen != null ? TdfDeletedBlock(generation: gen) : null),
    queueBlock: queue,
    evaluationTime: at ?? t(atSec),
  );

  TaskBoard syncBoards(
    TaskBoard primary,
    TaskBoard secondary, [
    TaskBoard? baseline,
    DateTime? at,
    int? ackGen,
    Map<String, TdfDeletionResolution> taskRes = const {},
  ]) => TaskBoardSync.merge(
    primary: primary,
    secondary: secondary,
    baseline: baseline,
    acknowledgedGeneration: ackGen,
    taskConflictResolutions: taskRes,
    evaluationTime: at ?? t(100),
  );

  Matcher throwsSyncOutcome(
    TdfSyncOutcomeKind kind, {
    Object? conflictedTasks = anything,
    Object? ambiguousTasks = anything,
    Object? ambiguousLabels = anything,
  }) => throwsA(
    isA<TdfSyncOutcomeException>()
        .having((error) => error.kind, 'kind', kind)
        .having((error) => error.conflictedTaskIds, 'conf', conflictedTasks)
        .having((error) => error.ambiguousTaskIds, 'ambTasks', ambiguousTasks)
        .having((error) => error.ambiguousLabelIds, 'ambLabs', ambiguousLabels),
  );

  group('TDF 0.5.0 Section 6.7.9 Three-Way Merge Table', () {
    const taskId = '8jKaCdOkD2';

    TaskBoard singleTaskBoard(String name, String? note, [int modSec = 10]) =>
        evalBoard([
          makeTask(taskId, name, modSec, 0, const [], const [], note),
        ]);

    final baseline = singleTaskBoard('N0', 'Q0', 10);

    test('executes all 6 scalar verification table cases symmetrically in both (L, R) and (R, L) directions', () {
      final cases = [
        ('Independent edits', 'N1', 'Q0', 11, 'N0', 'Q1', 12, 'N1', 'Q1', 13),
        ('Matching edits', 'N1', 'Q0', 11, 'N1', 'Q0', 12, 'N1', 'Q0', 12),
        ('Same field conflict', 'N1', 'Q0', 11, 'N2', 'Q0', 12, 'N2', 'Q0', 12),
        ('Equal ts', 'Alpha', 'Q0', 12, 'Zulu', 'Q0', 12, 'Zulu', 'Q0', 12),
        ('Conflict', 'N1', 'Alpha', 11, 'N0', 'Zulu', 12, 'N1', 'Zulu', 13),
        ('Unstamped edit', 'N0', 'Q0', 20, 'N1', 'Q0', 10, 'N1', 'Q0', 21),
      ];

      for (final (desc, lN, lQ, lT, rN, rQ, rT, eN, eQ, eT) in cases) {
        final local = singleTaskBoard(lN, lQ, lT);
        final incoming = singleTaskBoard(rN, rQ, rT);
        for (final (dir, first, second) in [
          ('forward', local, incoming),
          ('reversed', incoming, local),
        ]) {
          final merged = syncBoards(
            first,
            second,
            baseline,
            t(500),
          ).findTask(taskId)!;
          expect(merged.title, equals(eN), reason: '$desc ($dir): name');
          expect(merged.note, equals(eQ), reason: '$desc ($dir): note');
          expect(merged.modifiedAt, equals(t(eT)), reason: '$desc ($dir): rev');
        }
      }

      final b11 = singleTaskBoard('N1', 'Q0', 11);
      final b12 = singleTaskBoard('N0', 'Q1', 12);
      for (final (first, second) in [(b11, b12), (b12, b11)]) {
        final winner = syncBoards(
          first,
          second,
          null,
          t(500),
        ).findTask(taskId)!;
        expect(winner.title, equals('N0'));
        expect(winner.note, equals('Q1'));
        expect(winner.modifiedAt, equals(t(12)));
      }
    });

    test('combines independent label additions and removals, preserves atomic task occurrence state by completion counter, compares UTF-8 supplementary characters, and preserves revisions on idempotent re-merge', () {
      const l1 = '000001OkD2';
      const l2 = '000002OkD2';
      const l3 = '000003OkD2';
      const labels = <TdfLabel>[
        TdfLabel(id: l1, name: 'L1'),
        TdfLabel(id: l2, name: 'L2'),
        TdfLabel(id: l3, name: 'L3'),
      ];
      final queue = makeQueue(10, const [taskId]);
      TaskBoard boardFor(TaskItem item) =>
          evalBoard([item], queue, 100, null, labels);

      final baseTask = makeTask(taskId, 'Recurring Task', 10, 1, const [l1, l2])
          .copyWith(
            repeatRule: const TaskRepeatRule(count: 1, unit: RepeatUnit.days),
          );
      final baseBoard = boardFor(baseTask);
      final localBoard = boardFor(
        baseTask.copyWith(
          labelIds: const [l2],
          completions: 2,
          suspendedAt: t(86400),
          modifiedAt: t(11),
        ),
      );
      final remoteBoard = boardFor(
        baseTask.copyWith(
          labelIds: const [l1, l2, l3],
          completions: 1,
          suspendedAt: t(3600),
          modifiedAt: t(15),
        ),
      );

      final merged = syncBoards(localBoard, remoteBoard, baseBoard);
      final mergedTask = merged.findTask(taskId)!;

      expect(
        mergedTask.labelIds,
        equals([l2, l3]),
        reason: 'Label set must combine removal of l1 and addition of l3',
      );
      expect(
        mergedTask.completions,
        equals(2),
        reason: 'Greater completion counter (2 > 1) must win',
      );
      expect(mergedTask.suspendedAt, equals(t(86400)));
      expect(mergedTask.modifiedAt, equals(t(16)));

      final remerged = syncBoards(merged, merged, merged, t(200));
      expect(remerged.findTask(taskId)!.modifiedAt, equals(t(16)));

      final utf8Winner = syncBoards(
        singleTaskBoard('\uFF21', null, 12),
        singleTaskBoard('🚀', null, 12),
      );
      expect(
        utf8Winner.findTask(taskId)!.title,
        equals('🚀'),
        reason: 'UTF-8 byte comparison ranks U+1F680 above U+FF21',
      );
    });

    test('produces identical merge results for equivalent quoting, escaping, decimal GPS strings, and inline vs block condition syntax, and rejects merged dependency cycles', () {
      const parser = TdfService();
      const docA = '''
tdf 0.8.0
location loc001OkD2 {
    name 'Munich HQ'
    coordinates 048.13715400 -000.000
    radius 0250.00
}
label 000001OkD2 {
    name 'Work & Ops'
    condition location loc001OkD2
}
''';
      const docB = '''
tdf 0.8.0
location loc001OkD2 {
    name "Munich HQ"
    coordinates 48.137154 0
    radius 250
}
label 000001OkD2 {
    name "Work & Ops"
    condition {
        location loc001OkD2
    }
}
''';
      final boardA = parser.parse(docA, evaluationTime: t(100));
      final boardB = parser.parse(docB, evaluationTime: t(100));

      final merged = syncBoards(boardA, boardB, boardA);
      expect(
        merged.locations.single.modifiedAt,
        isNull,
        reason:
            'Equivalent decoded location payloads must not advance revision',
      );
      expect(
        merged.labels.single.modifiedAt,
        isNull,
        reason: 'Equivalent decoded payloads must not advance revision',
      );

      const idA = '00000AOkD2';
      const idB = '00000BOkD2';
      final leftBoard = evalBoard([
        makeTask(idA, 'A blocked by B', 20, 0, const [], const [
          TdfTaskDependency(taskId: idB),
        ]),
        makeTask(idB, 'B unblocked'),
      ]);
      final rightBoard = evalBoard([
        makeTask(idA, 'A unblocked'),
        makeTask(idB, 'B blocked by A', 20, 0, const [], const [
          TdfTaskDependency(taskId: idA),
        ]),
      ]);

      expect(
        () => syncBoards(leftBoard, rightBoard),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.circularDependency,
          ),
        ),
        reason: 'Combined dependency cycle A -> B -> A must fail validation',
      );
    });
  });

  group('TDF 0.5.0 Section 6.8 Deletion Records & Recovery', () {
    const taskId = '8jKaCdOkD2';
    const task2Id = '3nQp7ROkB8';
    const labelId = 'work00OkD2';

    test('enforces exact 30-day (2,592,000s) deletion record expiry, single generation increment across multiple expiries, and nonzero generation retention', () {
      final delTime = DateTime.utc(2026, 10, 5, 12, 0, 0);
      final exactly30Days = delTime.add(const Duration(seconds: 2592000));
      final over30Days = delTime.add(const Duration(seconds: 2592001));
      final delBlock = TdfDeletedBlock(
        generation: 0,
        tasks: [
          TdfDeletedTaskRecord(
            taskId: taskId,
            deletedAt: delTime,
            completionsCheckpoint: 4,
          ),
        ],
        labels: [TdfDeletedLabelRecord(labelId: labelId, deletedAt: delTime)],
      );
      final bRec = evalBoard(
        const [],
        null,
        100,
        null,
        const [],
        delBlock,
        exactly30Days,
      );

      final mergedAt30Days = syncBoards(bRec, bRec, bRec, exactly30Days);
      expect(mergedAt30Days.deletedBlock.generation, equals(0));
      expect(mergedAt30Days.deletedBlock.totalRecords, equals(2));

      final mergedOver30Days = syncBoards(bRec, bRec, bRec, over30Days);
      expect(
        mergedOver30Days.deletedBlock.generation,
        equals(1),
        reason: 'Expiring multiple records increments generation once',
      );
      expect(mergedOver30Days.deletedBlock.totalRecords, equals(0));
      expect(
        mergedOver30Days.deletedBlock.isDefaultEmpty,
        isFalse,
        reason: 'Nonzero generation keeps deleted block non-default',
      );
    });

    test('handles DeletionConflict, Delete and Undelete resolutions with completion checkpoint preservation, and single generation increment when combined with cleanup', () {
      final baseTask = makeTask(taskId, 'Original Task', 10, 3, const [
        labelId,
      ]);
      const baseLabel = TdfLabel(id: labelId, name: 'Work');
      final queue = makeQueue(10, const [taskId]);
      final baseline = evalBoard(
        [baseTask],
        queue,
        10,
        null,
        const [baseLabel],
      );
      final edited = baseTask.copyWith(
        title: 'Edited Task',
        completions: 5,
        modifiedAt: t(15),
      );
      final localBoard = evalBoard(
        [edited],
        queue,
        15,
        null,
        const [baseLabel],
      );
      final delRec = TdfDeletedTaskRecord(
        taskId: taskId,
        deletedAt: t(20),
        completionsCheckpoint: 7,
      );
      final remoteBoard = evalBoard(const [], null, 20, null, const [
        baseLabel,
      ], TdfDeletedBlock(generation: 0, tasks: [delRec]));

      for (final (first, second) in [
        (localBoard, remoteBoard),
        (remoteBoard, localBoard),
      ]) {
        expect(
          () => syncBoards(first, second, baseline, t(30)),
          throwsSyncOutcome(
            TdfSyncOutcomeKind.deletionConflict,
            conflictedTasks: contains(taskId),
          ),
        );
      }

      const delMap = {taskId: TdfDeletionResolution.delete};
      final resolvedDelete = syncBoards(
        localBoard,
        remoteBoard,
        baseline,
        t(30),
        null,
        delMap,
      );
      expect(resolvedDelete.findTask(taskId), isNull);
      expect(resolvedDelete.deletedBlock.generation, equals(0));
      final deleteRecord = resolvedDelete.deletedBlock.findTaskRecord(taskId)!;
      expect(deleteRecord.deletedAt, equals(t(30)));
      expect(deleteRecord.completionsCheckpoint, equals(7));

      const undelMap = {taskId: TdfDeletionResolution.undelete};
      final resolvedUndelete = syncBoards(
        localBoard,
        remoteBoard,
        baseline,
        t(18),
        null,
        undelMap,
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
      final sharedTask = makeTask(taskId, 'Shared Task', 10, 4);
      final queue = makeQueue(10, const [taskId]);
      final baseline = evalBoard([sharedTask], queue, 10, 2);
      final rolledBackRemote = evalBoard([sharedTask], queue, 20, 1);
      expect(
        () => syncBoards(baseline, rolledBackRemote, baseline, t(20), 2),
        throwsSyncOutcome(TdfSyncOutcomeKind.syncGenerationRollback),
      );

      final regressedTask = sharedTask.copyWith(
        completions: 3,
        modifiedAt: t(15),
      );
      final regressedLocal = evalBoard([regressedTask], queue, 20, 2);
      expect(
        () => syncBoards(regressedLocal, baseline, baseline, t(20), 2),
        throwsSyncOutcome(TdfSyncOutcomeKind.recoveryRequired),
      );

      const ambLabelId = 'ambLabOkD2';
      const ambTask1Id = 'ambT01OkD2';
      const ambTask2Id = 'ambT02OkD2';
      const ambLabel = TdfLabel(id: ambLabelId, name: 'Ambiguous Label');
      final ambTask1 = makeTask(
        ambTask1Id,
        'Ambiguous Prerequisite',
        11,
        0,
        const [ambLabelId],
      );
      final ambTask2 = makeTask(
        ambTask2Id,
        'Ambiguous Dependent',
        12,
        0,
        const [ambLabelId],
        const [TdfTaskDependency(taskId: ambTask1Id, requiredCompletion: 2)],
      );

      final localWithAmbiguous = evalBoard(
        [sharedTask, ambTask1, ambTask2],
        makeQueue(12, const [taskId, ambTask1Id, ambTask2Id]),
        20,
        2,
        const [ambLabel],
      );
      final advancedShared = evalBoard(const [], null, 20, 3);

      expect(
        () =>
            syncBoards(localWithAmbiguous, advancedShared, baseline, t(20), 2),
        throwsSyncOutcome(
          TdfSyncOutcomeKind.recoveryRequired,
          ambiguousTasks: containsAll([ambTask1Id, ambTask2Id]),
          ambiguousLabels: contains(ambLabelId),
        ),
      );

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
        reason: 'Unchanged cached sharedTask must be discarded',
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
        equals([TdfTaskDependency(taskId: recTask1.id, requiredCompletion: 2)]),
        reason: 'Recovered dependent must rewrite prerequisite ID',
      );
    });

    test('creates a deletion record when a compatible baseline proves an external deletion without an existing record', () {
      final task1 = makeTask(taskId, 'Task 1', 10, 2);
      final task2 = makeTask(task2Id, 'Task 2');
      final baseline = evalBoard(
        [task1, task2],
        makeQueue(10, const [taskId, task2Id]),
        10,
      );
      final extDeleted = evalBoard([task2], makeQueue(10, const [task2Id]), 10);

      final merged = syncBoards(baseline, extDeleted, baseline, t(25));
      expect(merged.findTask(taskId), isNull);
      final createdRecord = merged.deletedBlock.findTaskRecord(taskId);
      expect(createdRecord, isNotNull);
      expect(createdRecord!.deletedAt, equals(t(25)));
      expect(createdRecord.completionsCheckpoint, equals(2));
    });

    test('handles location three-way merge, location DeletionConflict, Delete and Undelete resolutions, Someday Undelete queue preservation, and ambiguous location recovery with condition reference rewriting', () {
      const locId = 'locHomOkD2';
      const baseLoc = TdfLocation(
        id: locId,
        name: 'Home',
        rawLatitudeText: '48.100000',
        rawLongitudeText: '11.500000',
        latitude: 48.1,
        longitude: 11.5,
        source: 'Old Addr',
        rawRadiusText: '100',
        radius: 100.0,
      );
      final baseWithLoc = TaskBoard.evaluate(
        tasks: [makeTask(taskId, 'Someday Task', 10)],
        locations: [baseLoc.copyWith(modifiedAt: t(10))],
        evaluationTime: t(10),
      );
      final localEditedLoc = TaskBoard.evaluate(
        tasks: [makeTask(taskId, 'Someday Task Edited', 15)],
        locations: [
          baseLoc.copyWith(
            latitudeText: '48.200000',
            longitudeText: '11.600000',
            latitude: 48.2,
            longitude: 11.6,
            source: 'New Addr',
            modifiedAt: t(15),
          ),
        ],
        evaluationTime: t(15),
      );
      final remoteDeletedBoth = TaskBoard.evaluate(
        tasks: const [],
        locations: const [],
        deletedBlock: TdfDeletedBlock(
          generation: 0,
          tasks: [
            TdfDeletedTaskRecord(
              taskId: taskId,
              deletedAt: t(20),
              completionsCheckpoint: 0,
            ),
          ],
          locations: [
            TdfDeletedLocationRecord(locationId: locId, deletedAt: t(20)),
          ],
        ),
        evaluationTime: t(20),
      );

      expect(
        () => TaskBoardSync.merge(
          primary: localEditedLoc,
          secondary: remoteDeletedBoth,
          baseline: baseWithLoc,
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
              )
              .having(
                (error) => error.conflictedLocationIds,
                'conflictedLocationIds',
                contains(locId),
              ),
        ),
      );

      final undeleted = TaskBoardSync.merge(
        primary: localEditedLoc,
        secondary: remoteDeletedBoth,
        baseline: baseWithLoc,
        taskConflictResolutions: const {taskId: TdfDeletionResolution.undelete},
        locationConflictResolutions: const {
          locId: TdfDeletionResolution.undelete,
        },
        evaluationTime: t(30),
      );
      expect(undeleted.findLocation(locId)?.source, equals('New Addr'));
      expect(undeleted.deletedBlock.findLocationRecord(locId), isNull);
      expect(
        undeleted.queueBlock.taskIds,
        isEmpty,
        reason: 'Undeleted task that was in Someday on surviving side must stay out of queue',
      );
      expect(undeleted.someday.map((item) => item.id), equals([taskId]));

      final ambLocBoard = TaskBoard.evaluate(
        tasks: [
          makeTask(taskId, 'Loc Task', 12).copyWith(
            conditions: const [
              LocationTaskCondition(locationIds: [locId]),
            ],
          ),
        ],
        labels: const [
          TdfLabel(
            id: labelId,
            name: 'Loc Label',
            conditions: [
              LocationTaskCondition(locationIds: [locId]),
            ],
          ),
        ],
        locations: [baseLoc.copyWith(modifiedAt: t(12))],
        deletedBlock: TdfDeletedBlock(generation: 1),
        evaluationTime: t(20),
      );
      final advancedShared = TaskBoard.evaluate(
        tasks: const [],
        deletedBlock: TdfDeletedBlock(generation: 2),
        evaluationTime: t(20),
      );

      expect(
        () => TaskBoardSync.merge(
          primary: ambLocBoard,
          secondary: advancedShared,
          acknowledgedGeneration: 1,
          evaluationTime: t(25),
        ),
        throwsA(
          isA<TdfSyncOutcomeException>()
              .having(
                (error) => error.kind,
                'kind',
                TdfSyncOutcomeKind.recoveryRequired,
              )
              .having(
                (error) => error.ambiguousLocationIds,
                'ambiguousLocationIds',
                contains(locId),
              ),
        ),
      );

      final recovered = TaskBoardSync.recoverAmbiguousEntities(
        localBoard: ambLocBoard,
        sharedBoard: advancedShared,
        recoverTaskIds: const [taskId],
        recoverLabelIds: const [labelId],
        recoverLocationIds: const [locId],
        evaluationTime: t(30),
      );
      expect(recovered.locations.length, equals(1));
      final newLocId = recovered.locations.single.id;
      expect(newLocId, isNot(equals(locId)));
      final recLabelCond =
          recovered.labels.single.conditions.single as LocationTaskCondition;
      expect(recLabelCond.locationIds, equals([newLocId]));
      final recTaskCond =
          recovered.allTasks.single.conditions.single as LocationTaskCondition;
      expect(recTaskCond.locationIds, equals([newLocId]));
    });

    test('recoverAmbiguousEntities rewrites references on shared surviving local labels and tasks and validateMergedGraphAndBounds enforces Section 6.7.7 resource bounds', () {
      const locAmb = 'LocAmbOkD2';
      const labelAmb = 'LblAmbOkD2';
      const taskAmb = 'TskAmbOkD2';
      const labelShared = 'LblShrOkD2';
      const taskShared = 'TskShrOkD2';

      final sharedLabelOnRemote = TdfLabel(
        id: labelShared,
        name: 'Shared Label',
        modifiedAt: t(10),
      );
      final sharedTaskOnRemote = makeTask(taskShared, 'Shared Task', 10);
      final sharedBoard = TaskBoard.evaluate(
        tasks: [sharedTaskOnRemote],
        labels: [sharedLabelOnRemote],
        deletedBlock: TdfDeletedBlock(generation: 2),
        evaluationTime: t(20),
      );

      final localBoard = TaskBoard.evaluate(
        tasks: [
          makeTask(taskAmb, 'Ambiguous Task', 12),
          sharedTaskOnRemote.copyWith(
            labelIds: const [labelAmb],
            dependencies: const [
              TdfTaskDependency(taskId: taskAmb, requiredCompletion: 2),
            ],
            conditions: const [
              LocationTaskCondition(locationIds: [locAmb]),
            ],
            modifiedAt: t(15),
          ),
        ],
        labels: [
          TdfLabel(id: labelAmb, name: 'Ambiguous Label', modifiedAt: t(12)),
          sharedLabelOnRemote.copyWith(
            conditions: const [
              LocationTaskCondition(locationIds: [locAmb]),
            ],
            modifiedAt: t(15),
          ),
        ],
        locations: [
          TdfLocation(
            id: locAmb,
            name: 'Ambiguous Location',
            latitude: 48.1,
            longitude: 11.5,
            radius: 150,
            modifiedAt: t(12),
          ),
        ],
        deletedBlock: TdfDeletedBlock(generation: 1),
        evaluationTime: t(20),
      );

      final recoveredBoard = TaskBoardSync.recoverAmbiguousEntities(
        localBoard: localBoard,
        sharedBoard: sharedBoard,
        recoverTaskIds: const [taskAmb],
        recoverLabelIds: const [labelAmb],
        recoverLocationIds: const [locAmb],
        evaluationTime: t(30),
      );

      final newLocId = recoveredBoard.locations.single.id;
      final newLabelId = recoveredBoard.labels
          .firstWhere((label) => label.id != labelShared)
          .id;
      final newTaskId = recoveredBoard.allTasks
          .firstWhere((task) => task.id != taskShared)
          .id;

      final mergedSharedLabel = recoveredBoard.findLabel(labelShared)!;
      final sharedLabelLocCond =
          mergedSharedLabel.conditions.single as LocationTaskCondition;
      expect(
        sharedLabelLocCond.locationIds,
        equals([newLocId]),
        reason: 'Shared surviving label referencing recovered location must be rewritten',
      );
      expect(mergedSharedLabel.modifiedAt, equals(t(30)));

      final mergedSharedTask = recoveredBoard.findTask(taskShared)!;
      expect(
        mergedSharedTask.labelIds,
        equals([newLabelId]),
        reason: 'Shared surviving task referencing recovered label must be rewritten',
      );
      expect(
        mergedSharedTask.dependencies,
        equals([TdfTaskDependency(taskId: newTaskId, requiredCompletion: 2)]),
        reason: 'Shared surviving task referencing recovered prerequisite must be rewritten',
      );
      final sharedTaskLocCond =
          mergedSharedTask.conditions.single as LocationTaskCondition;
      expect(
        sharedTaskLocCond.locationIds,
        equals([newLocId]),
        reason: 'Shared surviving task referencing recovered location must be rewritten',
      );
      expect(mergedSharedTask.modifiedAt, equals(t(30)));

      // Section 6.7.7 post-merge resource bounds in validateMergedGraphAndBounds:
      final tooManyLocations = <TdfLocation>[
        for (var i = 0; i <= maxTdfLocations; i++)
          TdfLocation(
            id: 'Loc${i.toString().padLeft(7, '0')}',
            name: 'Loc $i',
            latitude: 48.0,
            longitude: 11.0,
            radius: 100.0,
          ),
      ];
      expect(
        () => TaskBoardSync.validateMergedGraphAndBounds(
          const [],
          const [],
          tooManyLocations,
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason: 'Exceeding maxTdfLocations (200) must throw limitExceeded',
      );

      final tooManyLabelIds = <String>[
        for (var i = 0; i <= maxTdfArgsPerStmt; i++)
          'Lbl${i.toString().padLeft(7, '0')}',
      ];
      expect(
        () => TaskBoardSync.validateMergedGraphAndBounds([
          makeTask('TskLblLim1', 'Task').copyWith(labelIds: tooManyLabelIds),
        ], const []),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason: 'Task with > 64 labelIds must throw limitExceeded',
      );

      final tooManyDependencies = <TdfTaskDependency>[
        for (var i = 0; i <= maxTdfArgsPerStmt; i++)
          TdfTaskDependency(taskId: 'Dep${i.toString().padLeft(7, '0')}'),
      ];
      expect(
        () => TaskBoardSync.validateMergedGraphAndBounds([
          makeTask(
            'TskDepLim1',
            'Task',
          ).copyWith(dependencies: tooManyDependencies),
        ], const []),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason: 'Task with > 64 dependencies must throw limitExceeded',
      );

      final tooManyLocRefs = <String>[
        for (var i = 0; i <= maxTdfLocationRefsPerEntity; i++)
          'Loc${i.toString().padLeft(7, '0')}',
      ];
      expect(
        () => TaskBoardSync.validateMergedGraphAndBounds([
          makeTask('TskLocLim1', 'Task').copyWith(
            conditions: [LocationTaskCondition(locationIds: tooManyLocRefs)],
          ),
        ], const []),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason: 'Task with > 63 location refs must throw limitExceeded',
      );
      expect(
        () => TaskBoardSync.validateMergedGraphAndBounds(const [], [
          TdfLabel(
            id: 'LblLocLim1',
            name: 'Label',
            conditions: [LocationTaskCondition(locationIds: tooManyLocRefs)],
          ),
        ]),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason: 'Label with > 63 location refs must throw limitExceeded',
      );
    });
  });

  group('TDF 0.5.1 Section 6.11.2 Shared Queue Sync', () {
    const id1 = '000001OkD2';
    const id2 = '000002OkD2';
    const id3 = '000003OkD2';

    test('merges shared queue order via three-way baseline rules, preserves Someday <-> scheduled transitions without task.modified changes, filters completed tasks, appends concurrent additions by ascending UTC created then ASCII ID, and computes deterministic queue revision', () {
      final t1 = makeTask(id1, 'Task 1');
      final t2 = makeTask(
        id2,
        'Task 2',
      ).copyWith(createdAt: defaultCreated.add(const Duration(seconds: 1)));
      final baseline = evalBoard([t1, t2], makeQueue(10, const [id1, id2]), 10);

      final localSomeday = evalBoard([t1, t2], makeQueue(12, const [id1]), 12);
      final mergedToSomeday = syncBoards(localSomeday, baseline, baseline);
      expect(
        mergedToSomeday.queueBlock.taskIds,
        equals([id1]),
        reason: 'Moving scheduled task to Someday on L keeps L.queue',
      );
      expect(
        mergedToSomeday.someday.map((task) => task.id),
        equals([id2]),
        reason: 't2 must be in Someday after merging L.queue removal',
      );

      final localBoard = evalBoard(
        [t1, t2],
        makeQueue(15, const [id2, id1]),
        15,
      );
      final t3 = makeTask(
        id3,
        'Task 3 Added',
        18,
      ).copyWith(createdAt: defaultCreated.add(const Duration(seconds: 3)));
      final remoteBoard = evalBoard(
        [t1, t2, t3],
        makeQueue(18, const [id1, id2, id3]),
        18,
      );

      final mergedConflict = syncBoards(localBoard, remoteBoard, baseline);
      expect(mergedConflict.queueBlock.taskIds, equals([id1, id2, id3]));
      expect(mergedConflict.queueBlock.modifiedAt, equals(t(18)));

      final localNewerQueue = evalBoard(
        [t1, t2],
        makeQueue(20, const [id2, id1]),
        20,
      );
      for (final (first, second) in [
        (localNewerQueue, remoteBoard),
        (remoteBoard, localNewerQueue),
      ]) {
        final board = syncBoards(first, second, baseline);
        expect(board.queueBlock.taskIds, equals([id2, id1, id3]));
        expect(
          board.queueBlock.modifiedAt,
          equals(t(21)),
          reason: 'Reconciled queue advances to greatest queue revision + 1s',
        );
      }
    });
  });

  group('WorkspaceSyncState Binary Codec & Persistence', () {
    test('round-trips WorkspaceSyncState TTS\\x04 binary encoding across all 8 fields, rejects non-v4 headers, and enforces atomic per-target validation in constructor and fromBytes', () async {
      const localHex =
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      const remoteHex =
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
      final state = WorkspaceSyncState(
        lastSyncedLocalTdf: 'tdf 0.8.0\n\ntask 000001OkD2 {\n    name    "Local"\n    created 2026-11-01 08:00\n}\n',
        lastSyncedRemoteTdf: 'tdf 0.8.0\n\ntask 000001OkD2 {\n    name    "Remote"\n    created 2026-11-01 08:00\n}\n',
        acknowledgedLocalGeneration: 4,
        acknowledgedRemoteGeneration: 7,
        localSourceDigest: localHex,
        remoteSourceDigest: remoteHex,
      );

      final encodedBytes = state.toBytes();
      expect(
        encodedBytes.sublist(0, 4),
        equals(<int>[0x54, 0x54, 0x53, 0x04]),
        reason: 'Must encode TTS\\x04 header',
      );
      final decoded = WorkspaceSyncState.fromBytes(encodedBytes);
      expect(decoded, equals(state));
      expect(decoded.hashCode, equals(state.hashCode));
      expect(decoded.acknowledgedLocalGeneration, equals(4));
      expect(decoded.acknowledgedRemoteGeneration, equals(7));
      expect(decoded.localSourceDigest, equals(localHex));
      expect(decoded.remoteSourceDigest, equals(remoteHex));
      expect(
        WorkspaceSyncState.fromBytes(Uint8List(0)),
        equals(WorkspaceSyncState.empty),
      );
      for (final version in <int>[1, 2, 3, 5]) {
        final wrongHeader = Uint8List.fromList(<int>[
          0x54,
          0x54,
          0x53,
          version,
          ...encodedBytes.sublist(4),
        ]);
        expect(
          WorkspaceSyncState.fromBytes(wrongHeader),
          equals(WorkspaceSyncState.empty),
          reason:
              'TTS\\x0$version must be rejected to WorkspaceSyncState.empty',
        );
      }

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

      final withRemoteValidators = state.copyWith(
        remoteEtag: '"etag-v1-a1b2c3"',
        remoteLastModified: 'Mon, 09 Nov 2026 22:00:00 GMT',
      );
      expect(withRemoteValidators.remoteEtag, equals('"etag-v1-a1b2c3"'));
      expect(
        withRemoteValidators.remoteLastModified,
        equals('Mon, 09 Nov 2026 22:00:00 GMT'),
      );
      expect(withRemoteValidators, isNot(equals(state)));
      final validatorBytes = withRemoteValidators.toBytes();
      expect(validatorBytes[3], equals(4));
      final decodedValidators = WorkspaceSyncState.fromBytes(validatorBytes);
      expect(decodedValidators, equals(withRemoteValidators));
      expect(decodedValidators.hashCode, equals(withRemoteValidators.hashCode));

      final clearedValidators = decodedValidators.copyWith(
        clearRemoteEtag: true,
        clearRemoteLastModified: true,
      );
      expect(clearedValidators.remoteEtag, isNull);
      expect(clearedValidators.remoteLastModified, isNull);
      expect(clearedValidators, equals(state));

      // Verify atomic per-target invalidation across constructor, copyWith, AND raw fromBytes!
      BytesBuilder buildRawV4({
        String? localTdf,
        String? remoteTdf,
        int? localGen,
        int? remoteGen,
        String? localDigest,
        String? remoteDigest,
        String? etag,
        String? lastModified,
      }) {
        void writeStr(BytesBuilder b, String? s) {
          if (s == null) {
            b.addByte(0);
            return;
          }
          b.addByte(1);
          final utf8Bytes = s.codeUnits;
          final len = ByteData(4)..setUint32(0, utf8Bytes.length);
          b.add(len.buffer.asUint8List());
          b.add(utf8Bytes);
        }

        void writeGen(BytesBuilder b, int? g) {
          if (g == null) {
            b.addByte(0);
            return;
          }
          b.addByte(1);
          final data = ByteData(8)..setInt64(0, g);
          b.add(data.buffer.asUint8List());
        }

        final builder = BytesBuilder()
          ..add(const <int>[0x54, 0x54, 0x53, 0x04]);
        writeStr(builder, localTdf);
        writeStr(builder, remoteTdf);
        writeGen(builder, localGen);
        writeGen(builder, remoteGen);
        writeStr(builder, localDigest);
        writeStr(builder, remoteDigest);
        writeStr(builder, etag);
        writeStr(builder, lastModified);
        return builder;
      }

      // Raw wire payload with tdf 0.7.0 local header and valid remote fields:
      final rawBadLocal = buildRawV4(
        localTdf: 'tdf 0.7.0\n',
        remoteTdf: 'tdf 0.8.0\n',
        localGen: 2,
        remoteGen: 5,
        localDigest: localHex,
        remoteDigest: remoteHex,
        etag: '"ok"',
        lastModified: 'Wed, 11 Nov 2026 08:00:00 GMT',
      ).toBytes();
      final decodedBadLocal = WorkspaceSyncState.fromBytes(rawBadLocal);
      expect(decodedBadLocal.lastSyncedLocalTdf, isNull);
      expect(decodedBadLocal.acknowledgedLocalGeneration, isNull);
      expect(decodedBadLocal.localSourceDigest, isNull);
      expect(decodedBadLocal.lastSyncedRemoteTdf, equals('tdf 0.8.0\n'));
      expect(decodedBadLocal.acknowledgedRemoteGeneration, equals(5));
      expect(decodedBadLocal.remoteSourceDigest, equals(remoteHex));
      expect(decodedBadLocal.remoteEtag, equals('"ok"'));

      // Raw wire payload with negative remoteGen and valid local fields:
      final rawBadRemote = buildRawV4(
        localTdf: 'tdf 0.8.0\n',
        remoteTdf: 'tdf 0.8.0\n',
        localGen: 0,
        remoteGen: -1,
        localDigest: localHex,
        remoteDigest: remoteHex,
        etag: '"dropped"',
        lastModified: 'Wed, 11 Nov 2026 08:00:00 GMT',
      ).toBytes();
      final decodedBadRemote = WorkspaceSyncState.fromBytes(rawBadRemote);
      expect(decodedBadRemote.lastSyncedLocalTdf, equals('tdf 0.8.0\n'));
      expect(decodedBadRemote.acknowledgedLocalGeneration, equals(0));
      expect(decodedBadRemote.localSourceDigest, equals(localHex));
      expect(decodedBadRemote.lastSyncedRemoteTdf, isNull);
      expect(decodedBadRemote.acknowledgedRemoteGeneration, isNull);
      expect(decodedBadRemote.remoteSourceDigest, isNull);
      expect(decodedBadRemote.remoteEtag, isNull);
      expect(decodedBadRemote.remoteLastModified, isNull);

      // Uppercase SHA-256 hex digest is rejected by atomic validation:
      final upperHexState = WorkspaceSyncState(
        lastSyncedLocalTdf: 'tdf 0.8.0\n',
        acknowledgedLocalGeneration: 1,
        localSourceDigest: localHex.toUpperCase(),
        lastSyncedRemoteTdf: 'tdf 0.8.0\n',
        acknowledgedRemoteGeneration: 1,
        remoteSourceDigest: remoteHex,
      );
      expect(upperHexState.lastSyncedLocalTdf, isNull);
      expect(upperHexState.acknowledgedLocalGeneration, isNull);
      expect(upperHexState.localSourceDigest, isNull);
      expect(upperHexState.lastSyncedRemoteTdf, equals('tdf 0.8.0\n'));
    });
  });

  group('TDF 0.7.0 Payload Comparison, Reconciliation, Stage Fairness & Bounds', () {
    test('compares TdfLabel.links lexicographically and diverges v070 vs v060 TaskItem payload tie-breaks', () {
      const labelEmpty = TdfLabel(id: 'lbl0000001', name: 'Hub');
      const labelOneLink = TdfLabel(
        id: 'lbl0000001',
        name: 'Hub',
        links: <TaskLink>[TaskLink(title: 'Alpha', uri: 'https://a.example')],
      );
      const labelOneLinkHigherUri = TdfLabel(
        id: 'lbl0000001',
        name: 'Hub',
        links: <TaskLink>[TaskLink(title: 'Alpha', uri: 'https://b.example')],
      );
      const labelOneLinkHigherTitle = TdfLabel(
        id: 'lbl0000001',
        name: 'Hub',
        links: <TaskLink>[TaskLink(title: 'Beta', uri: 'https://a.example')],
      );
      const labelTwoLinks = TdfLabel(
        id: 'lbl0000001',
        name: 'Hub',
        links: <TaskLink>[
          TaskLink(title: 'Alpha', uri: 'https://a.example'),
          TaskLink(title: 'Beta', uri: 'https://b.example'),
        ],
      );

      expect(
        TdfPayloadComparison.compareLabelPayloads(labelEmpty, labelOneLink),
        lessThan(0),
      );
      expect(
        TdfPayloadComparison.compareLabelPayloads(
          labelOneLink,
          labelOneLinkHigherUri,
        ),
        lessThan(0),
      );
      expect(
        TdfPayloadComparison.compareLabelPayloads(
          labelOneLinkHigherUri,
          labelOneLinkHigherTitle,
        ),
        lessThan(0),
      );
      expect(
        TdfPayloadComparison.compareLabelPayloads(labelOneLink, labelTwoLinks),
        lessThan(0),
        reason: 'Shorter link list prefix must sort before longer list',
      );

      // Canonical 0.8.0 order compares (name, note, created, labels, origin, link, history, condition, taskState):
      final earlierCreatedZeta = TaskItem(
        id: 'tie0000001',
        title: 'Zeta',
        createdAt: DateTime.utc(2026, 11, 1, 8, 0, 0),
        modifiedAt: t(10),
      );
      final laterCreatedAlpha = TaskItem(
        id: 'tie0000001',
        title: 'Alpha',
        createdAt: DateTime.utc(2026, 11, 1, 9, 0, 0),
        modifiedAt: t(10),
      );
      expect(
        TdfPayloadComparison.compareTaskPayloads(
          earlierCreatedZeta,
          laterCreatedAlpha,
        ),
        greaterThan(0),
        reason: 'Canonical payload order compares name ("Zeta" > "Alpha") before createdAt',
      );

      final withConditionOnly = TaskItem(
        id: 'tie0000002',
        title: 'Same',
        createdAt: defaultCreated,
        conditions: <TaskCondition>[
          DayTaskCondition.fromWeekdays(const <int>[DateTime.monday]),
        ],
      );
      final withLinkOnly = TaskItem(
        id: 'tie0000002',
        title: 'Same',
        createdAt: defaultCreated,
        links: const <TaskLink>[
          TaskLink(title: 'Doc', uri: 'https://example.com'),
        ],
      );
      expect(
        TdfPayloadComparison.compareTaskPayloads(
          withLinkOnly,
          withConditionOnly,
        ),
        greaterThan(0),
        reason: 'Canonical payload order compares link before condition',
      );
    });

    test('compares 0.7.0 Task state tuples (suspended, due, repeat, history) and taskPayloadsEqualModuloBlockCleanup', () {
      final base = TaskItem(
        id: 'tup0000001',
        title: 'Tuple Task',
        createdAt: defaultCreated,
      );
      final finNoNote = base.copyWith(suspendedAt: t(500));
      final finNoteA = base.copyWith(
        suspendedAt: t(500),
        suspendedNote: 'Alpha',
      );
      final finNoteB = base.copyWith(
        suspendedAt: t(500),
        suspendedNote: 'Beta',
      );
      final foreverNoNote = base.copyWith(isSuspendedForever: true);
      final foreverNoteA = base.copyWith(
        isSuspendedForever: true,
        suspendedNote: 'Alpha',
      );
      final foreverNoteB = base.copyWith(
        isSuspendedForever: true,
        suspendedNote: 'Beta',
      );

      final deferralChain = <TaskItem>[
        base,
        finNoNote,
        finNoteA,
        finNoteB,
        foreverNoNote,
        foreverNoteA,
        foreverNoteB,
      ];
      for (var i = 0; i < deferralChain.length - 1; i++) {
        expect(
          TdfPayloadComparison.compareTaskStates(
            deferralChain[i],
            deferralChain[i + 1],
          ),
          lessThan(0),
          reason: 'Deferral tuple order failed at index $i',
        );
      }

      final dueActiveNoNote = base.copyWith(dueAt: t(600));
      final dueActiveNote = base.copyWith(dueAt: t(600), dueNote: 'Cutoff');
      final duePassiveNoNote = base.copyWith(dueAt: t(600), isDuePassive: true);
      final duePassiveNote = base.copyWith(
        dueAt: t(600),
        isDuePassive: true,
        dueNote: 'Cutoff',
      );
      final dueChain = <TaskItem>[
        base,
        dueActiveNoNote,
        dueActiveNote,
        duePassiveNoNote,
        duePassiveNote,
      ];
      for (var i = 0; i < dueChain.length - 1; i++) {
        expect(
          TdfPayloadComparison.compareTaskStates(dueChain[i], dueChain[i + 1]),
          lessThan(0),
          reason: 'Due tuple order failed at index $i',
        );
      }

      final repLead0 = base.copyWith(
        repeatRule: const TaskRepeatRule(
          count: 1,
          unit: RepeatUnit.weeks,
          leadDays: 0,
        ),
      );
      final repLead3 = base.copyWith(
        repeatRule: const TaskRepeatRule(
          count: 1,
          unit: RepeatUnit.weeks,
          leadDays: 3,
        ),
      );
      expect(
        TdfPayloadComparison.compareTaskStates(repLead0, repLead3),
        lessThan(0),
        reason: 'repeat leadDays 0 < 3',
      );

      final hist1 = base.copyWith(
        history: <TaskHistoryEntry>[
          TaskHistoryEntry(timestampUtc: t(10), text: 'First'),
        ],
      );
      final hist2 = base.copyWith(
        history: <TaskHistoryEntry>[
          TaskHistoryEntry(timestampUtc: t(10), text: 'First'),
          TaskHistoryEntry(timestampUtc: t(20), text: 'Second'),
        ],
      );
      expect(
        TdfPayloadComparison.compareTaskPayloads(hist1, hist2),
        lessThan(0),
        reason: 'Shorter history prefix < longer history',
      );
      expect(TdfPayloadComparison.taskPayloadsEqual(hist1, hist1), isTrue);
      expect(TdfPayloadComparison.taskPayloadsEqual(hist1, hist2), isFalse);

      // taskPayloadsEqualModuloBlockCleanup:
      final donePrereq = TaskItem(
        id: 'pre0000001',
        title: 'Done Prereq',
        createdAt: defaultCreated,
        completions: 1,
        isCompleted: true,
        completedAt: t(50),
      );
      final uncleanedOpen = base.copyWith(
        suspendedAt: t(90),
        suspendedNote: 'Expired',
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'pre0000001', requiredCompletion: 1),
          TdfTaskDependency(taskId: 'del0000001', requiredCompletion: 1),
        ],
      );
      expect(
        TdfPayloadComparison.taskPayloadsEqualModuloBlockCleanup(
          left: uncleanedOpen,
          right: base,
          liveTasksById: <String, TaskItem>{
            base.id: uncleanedOpen,
            donePrereq.id: donePrereq,
          },
          deletedTaskIds: const <String>{'del0000001'},
          nowUtc: t(100),
        ),
        isTrue,
      );
    });

    test('defers bystander post-merge block cleanup in Stage 1 (TdfCleanupMode.deferred) and cleans in Stage 2 without revision inflation', () {
      const bystanderId = 'bys0000001';
      const activeId = 'act0000001';
      final tBase = DateTime.utc(2026, 11, 11, 9, 0, 0);
      final tRemoteEdit = DateTime.utc(2026, 11, 11, 11, 0, 0);
      final tExpired = DateTime.utc(2026, 11, 11, 12, 0, 0);
      final tSyncNow = DateTime.utc(2026, 11, 11, 12, 5, 0);

      final bystanderBase = TaskItem(
        id: bystanderId,
        title: 'Original Bystander',
        createdAt: tBase,
        modifiedAt: tBase,
        suspendedAt: tExpired,
        suspendedNote: 'Wait until noon',
      );
      final activeBase = TaskItem(
        id: activeId,
        title: 'Active Local Task',
        createdAt: tBase,
        modifiedAt: tBase,
      );

      final localBaseline = TaskBoard.evaluate(
        tasks: <TaskItem>[bystanderBase, activeBase],
        evaluationTime: tBase,
      );
      final localDisk = TaskBoard.evaluate(
        tasks: <TaskItem>[
          bystanderBase,
          activeBase.copyWith(
            title: 'Local Disk Edit',
            modifiedAt: DateTime.utc(2026, 11, 11, 10, 0, 0),
          ),
        ],
        evaluationTime: tSyncNow,
      );
      final remoteBoard = TaskBoard.evaluate(
        tasks: <TaskItem>[
          bystanderBase.copyWith(
            title: 'Remote Bystander Title',
            modifiedAt: tRemoteEdit,
          ),
          activeBase,
        ],
        evaluationTime: tSyncNow,
      );

      // Stage 1: local sync with TdfCleanupMode.deferred
      final stage1Board = TaskBoardSync.merge(
        primary: localBaseline,
        secondary: localDisk,
        baseline: localBaseline,
        evaluationTime: tSyncNow,
        cleanupMode: TdfCleanupMode.deferred,
      );
      final stage1Bystander = stage1Board.findTask(bystanderId)!;
      expect(
        stage1Bystander.modifiedAt,
        equals(tBase),
        reason:
            'Stage 1 must not inflate bystander modifiedAt ahead of Stage 2',
      );
      expect(stage1Bystander.suspendedAt, equals(tExpired));
      expect(stage1Bystander.suspendedNote, equals('Wait until noon'));

      // Stage 2: remote sync with TdfCleanupMode.finalStage
      final stage2Board = TaskBoardSync.merge(
        primary: stage1Board,
        secondary: remoteBoard,
        baseline: localBaseline,
        evaluationTime: tSyncNow,
        cleanupMode: TdfCleanupMode.finalStage,
      );
      final stage2Bystander = stage2Board.findTask(bystanderId)!;
      expect(
        stage2Bystander.title,
        equals('Remote Bystander Title'),
        reason: 'Remote title edit must win because Stage 1 preserved tBase',
      );
      expect(stage2Bystander.suspendedAt, isNull);
      expect(stage2Bystander.suspendedNote, isNull);
      expect(stage2Bystander.modifiedAt, equals(tSyncNow));

      // stampAndNormalize respects cleanupMode: deferred vs finalStage
      final normalizedDeferred = TaskBoardSync.stampAndNormalize(
        localBaseline,
        evaluationTime: tSyncNow,
        cleanupMode: TdfCleanupMode.deferred,
      );
      expect(
        normalizedDeferred.findTask(bystanderId)!.suspendedAt,
        equals(tExpired),
      );
      final normalizedCleaned = TaskBoardSync.stampAndNormalize(
        localBaseline,
        evaluationTime: tSyncNow,
        cleanupMode: TdfCleanupMode.finalStage,
      );
      expect(normalizedCleaned.findTask(bystanderId)!.suspendedAt, isNull);
      expect(
        normalizedCleaned.findTask(bystanderId)!.modifiedAt,
        equals(tSyncNow),
      );
    });

    test('applies Section 6.8.4 baseline hygiene on generation advance and strips discardedTaskIds in recoverAmbiguousEntities', () {
      const cleanLocalOnlyId = 'cln0000001';
      const editedLocalOnlyId = 'edt0000001';
      const discardedLocalId = 'dsc0000001';
      const sharedOpenId = 'shr0000001';

      final tBase = DateTime.utc(2026, 11, 14, 8, 0, 0);
      final tExpired = DateTime.utc(2026, 11, 14, 12, 0, 0);
      final tNow = DateTime.utc(2026, 11, 14, 12, 5, 0);

      // 1. Local-only task whose ONLY diff vs baseline is expired suspended cleanup -> discarded cleanly without RecoveryRequired!
      final cleanTaskBase = TaskItem(
        id: cleanLocalOnlyId,
        title: 'Clean Local Task',
        createdAt: tBase,
        modifiedAt: tBase,
        suspendedAt: tExpired,
        suspendedNote: 'Noon callback',
      );
      final cleanTaskLocal = cleanTaskBase.copyWith(
        clearSuspendedAt: true,
        clearSuspendedNote: true,
        modifiedAt: DateTime.utc(2026, 11, 14, 12, 0, 1),
      );
      final baselineClean = TaskBoard.evaluate(
        tasks: <TaskItem>[cleanTaskBase],
        deletedBlock: TdfDeletedBlock(generation: 1),
        evaluationTime: tBase,
      );
      final localClean = TaskBoard.evaluate(
        tasks: <TaskItem>[cleanTaskLocal],
        deletedBlock: TdfDeletedBlock(generation: 1),
        evaluationTime: tNow,
      );
      final remoteGenAdvanced = TaskBoard.evaluate(
        tasks: const <TaskItem>[],
        deletedBlock: TdfDeletedBlock(generation: 2),
        evaluationTime: tNow,
      );

      final silentlyDiscarded = TaskBoardSync.merge(
        primary: localClean,
        secondary: remoteGenAdvanced,
        baseline: baselineClean,
        acknowledgedGeneration: 1,
        evaluationTime: tNow,
      );
      expect(
        silentlyDiscarded.findTask(cleanLocalOnlyId),
        isNull,
        reason: 'Block-cleanup-only local task must discard silently on remote generation advance',
      );

      // 2. Local-only task with history / leadDays edit vs remote generation advance -> RecoveryRequired, and recoverAmbiguousEntities strips discardedTaskIds from surviving open tasks!
      final editedBase = TaskItem(
        id: editedLocalOnlyId,
        title: 'Edited Ambiguous',
        createdAt: tBase,
        modifiedAt: tBase,
      );
      final discardedBase = TaskItem(
        id: discardedLocalId,
        title: 'Discarded Ambiguous',
        createdAt: tBase,
        modifiedAt: tBase,
      );
      final sharedTask = TaskItem(
        id: sharedOpenId,
        title: 'Shared Open Dependent',
        createdAt: tBase,
        modifiedAt: tBase,
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: editedLocalOnlyId, requiredCompletion: 1),
          TdfTaskDependency(taskId: discardedLocalId, requiredCompletion: 1),
        ],
      );
      final baselineAmbig = TaskBoard.evaluate(
        tasks: <TaskItem>[editedBase, discardedBase, sharedTask],
        deletedBlock: TdfDeletedBlock(generation: 1),
        evaluationTime: tBase,
      );
      final localAmbig = TaskBoard.evaluate(
        tasks: <TaskItem>[
          editedBase.copyWith(
            history: <TaskHistoryEntry>[
              TaskHistoryEntry(
                timestampUtc: DateTime.utc(2026, 11, 14, 10, 0, 0),
                text: 'Local progress',
              ),
            ],
            dependencies: const <TdfTaskDependency>[
              TdfTaskDependency(
                taskId: discardedLocalId,
                requiredCompletion: 1,
              ),
            ],
            modifiedAt: DateTime.utc(2026, 11, 14, 10, 0, 0),
          ),
          discardedBase.copyWith(
            dueAt: DateTime.utc(2026, 11, 20, 17, 0, 0),
            dueNote: 'Edited due note',
            modifiedAt: DateTime.utc(2026, 11, 14, 10, 5, 0),
          ),
          sharedTask,
        ],
        deletedBlock: TdfDeletedBlock(generation: 1),
        evaluationTime: tNow,
      );
      final remoteAmbig = TaskBoard.evaluate(
        tasks: <TaskItem>[
          sharedTask.copyWith(dependencies: const <TdfTaskDependency>[]),
        ],
        deletedBlock: TdfDeletedBlock(generation: 2),
        evaluationTime: tNow,
      );

      expect(
        () => TaskBoardSync.merge(
          primary: localAmbig,
          secondary: remoteAmbig,
          baseline: baselineAmbig,
          acknowledgedGeneration: 1,
          evaluationTime: tNow,
        ),
        throwsSyncOutcome(
          TdfSyncOutcomeKind.recoveryRequired,
          ambiguousTasks: containsAll(<String>[
            editedLocalOnlyId,
            discardedLocalId,
          ]),
        ),
      );

      // Recover ONLY editedLocalOnlyId and discard discardedLocalId:
      final recovered = TaskBoardSync.recoverAmbiguousEntities(
        localBoard: localAmbig,
        sharedBoard: remoteAmbig,
        baseline: baselineAmbig,
        recoverTaskIds: const <String>{editedLocalOnlyId},
        recoverLabelIds: const <String>{},
        evaluationTime: tNow,
      );
      expect(recovered.findTask(discardedLocalId), isNull);
      final newRecoveredTask = recovered.allTasks.singleWhere(
        (task) => task.id != sharedOpenId,
      );
      expect(
        newRecoveredTask.dependencies,
        isEmpty,
        reason: 'Recovered open task must strip blocked reference to discardedTaskIds',
      );
      expect(
        recovered.findTask(sharedOpenId)!.dependencies,
        equals(<TdfTaskDependency>[
          TdfTaskDependency(taskId: newRecoveredTask.id, requiredCompletion: 1),
        ]),
        reason: 'Shared open task must rewrite recovered prerequisite and strip discardedTaskIds',
      );
    });

    test(
      'enforces 0.7.0 vs 0.6.0 resource bounds in validateMergedGraphAndBounds',
      () {
        // 1. Label links: 20 accepted, 21 rejected
        final twentyLinks = <TaskLink>[
          for (var i = 0; i < maxTdfLinksPerLabel; i++)
            TaskLink(title: 'Link $i', uri: 'https://example.com/$i'),
        ];
        TaskBoardSync.validateMergedGraphAndBounds(
          const <TaskItem>[],
          <TdfLabel>[
            TdfLabel(id: 'lblLinks20', name: 'Valid 20', links: twentyLinks),
          ],
        );
        expect(
          () => TaskBoardSync.validateMergedGraphAndBounds(
            const <TaskItem>[],
            <TdfLabel>[
              TdfLabel(
                id: 'lblLinks21',
                name: 'Invalid 21',
                links: <TaskLink>[
                  ...twentyLinks,
                  const TaskLink(
                    title: 'Overflow',
                    uri: 'https://example.com/21',
                  ),
                ],
              ),
            ],
          ),
          throwsA(
            isA<TdfException>().having(
              (error) => error.kind,
              'kind',
              TdfErrorKind.limitExceeded,
            ),
          ),
        );

        // 2. Task links: 21 rejected
        expect(
          () => TaskBoardSync.validateMergedGraphAndBounds(<TaskItem>[
            makeTask('tskLinks21', 'Invalid 21').copyWith(
              links: <TaskLink>[
                ...twentyLinks,
                const TaskLink(
                  title: 'Overflow',
                  uri: 'https://example.com/21',
                ),
              ],
            ),
          ], const <TdfLabel>[]),
          throwsA(
            isA<TdfException>().having(
              (error) => error.kind,
              'kind',
              TdfErrorKind.limitExceeded,
            ),
          ),
        );

        // 3. Task with 500 history + 20 links (<= 1,024 direct statements) accepted; > 1,024 subtasks rejected!
        final maxHistory = <TaskHistoryEntry>[
          for (var i = 0; i < maxTdfHistoryPerTask; i++)
            TaskHistoryEntry(
              timestampUtc: defaultCreated.add(Duration(seconds: i)),
              text: 'Entry $i',
            ),
        ];
        final fullTask = makeTask(
          'tskFull080',
          'Full 080',
        ).copyWith(links: twentyLinks, history: maxHistory);
        expect(fullTask.canonicalDirectChildStatementCount, greaterThan(512));
        expect(
          fullTask.canonicalDirectChildStatementCount,
          lessThanOrEqualTo(maxTdfStmtsPerBlock),
        );
        TaskBoardSync.validateMergedGraphAndBounds(
          <TaskItem>[fullTask],
          const <TdfLabel>[],
          const <TdfLocation>[],
        );

        final tooManySubtasks = <SubtaskItem>[
          for (var i = 0; i <= maxTdfStmtsPerBlock; i++)
            SubtaskItem(title: 'Step $i'),
        ];
        expect(
          () => TaskBoardSync.validateMergedGraphAndBounds(
            <TaskItem>[
              makeTask(
                'tskSub1025',
                'Overflow Subtasks',
              ).copyWith(subtasks: tooManySubtasks),
            ],
            const <TdfLabel>[],
            const <TdfLocation>[],
          ),
          throwsA(
            isA<TdfException>().having(
              (error) => error.kind,
              'kind',
              TdfErrorKind.limitExceeded,
            ),
          ),
          reason: '1,025 subtasks must fail under MAX_STMTS_PER_BLOCK (1,024)',
        );
      },
    );
  });

  group('TDF 0.8.0 Schedule Anchors, Stage Fairness, Symmetric Refresh, Scoped Cascades & Bound Decisions', () {
    test('couples dueAnchor atomically in _compareDue, tie-breaks, M_clean == G revisions, Case 1 & Case 2 merges, payload signatures, and DeletionConflict screening', () {
      const id = 'anc0000001';
      final anchorEarly = TdfLocalDateTime(2026, 1, 31, 9, 0, 0);
      final anchorLate = TdfLocalDateTime(2026, 1, 31, 18, 0, 0);
      final dueUtc = DateTime.utc(2026, 2, 28, 17, 0, 0);

      final base = TaskItem(
        id: id,
        title: 'Monthly Report',
        createdAt: defaultCreated,
        modifiedAt: t(10),
      );
      final dueChain = <TaskItem>[
        base,
        base.copyWith(dueAt: dueUtc),
        base.copyWith(dueAt: dueUtc, dueNote: 'Cutoff'),
        base.copyWith(dueAt: dueUtc, isDuePassive: true),
        base.copyWith(dueAt: dueUtc, isDuePassive: true, dueNote: 'Cutoff'),
        base.copyWith(dueAt: dueUtc, dueAnchor: anchorEarly),
        base.copyWith(dueAt: dueUtc, dueAnchor: anchorLate),
        base.copyWith(
          dueAt: dueUtc,
          dueAnchor: anchorLate,
          isDuePassive: true,
          dueNote: 'Final',
        ),
      ];
      for (var i = 0; i < dueChain.length - 1; i++) {
        expect(
          TdfPayloadComparison.compareTaskStates(dueChain[i], dueChain[i + 1]),
          lessThan(0),
          reason: 'Atomic due 4-tuple order failed at index $i',
        );
        expect(
          TdfPayloadComparison.compareTaskPayloads(
            dueChain[i],
            dueChain[i + 1],
          ),
          lessThan(0),
          reason: 'Task payload order failed on dueAnchor at index $i',
        );
      }

      // Payload signature invariance to modifiedAt and sensitivity to dueAnchor / label / location fields:
      final withAnchorEarlyMod10 = base.copyWith(
        dueAt: dueUtc,
        dueAnchor: anchorEarly,
        modifiedAt: t(10),
      );
      final withAnchorEarlyMod99 = withAnchorEarlyMod10.copyWith(
        modifiedAt: t(99),
      );
      final withAnchorLateMod10 = base.copyWith(
        dueAt: dueUtc,
        dueAnchor: anchorLate,
        modifiedAt: t(10),
      );
      expect(
        TdfPayloadComparison.taskPayloadSignature(withAnchorEarlyMod10),
        equals(TdfPayloadComparison.taskPayloadSignature(withAnchorEarlyMod99)),
        reason: 'taskPayloadSignature must ignore modifiedAt',
      );
      expect(
        TdfPayloadComparison.taskPayloadSignature(withAnchorEarlyMod10),
        isNot(
          equals(
            TdfPayloadComparison.taskPayloadSignature(withAnchorLateMod10),
          ),
        ),
        reason: 'taskPayloadSignature must distinguish dueAnchor',
      );
      expect(
        TdfPayloadComparison.labelPayloadSignature(
          TdfLabel(
            id: 'lblSig0001',
            name: 'Ops',
            color: '#aabbcc',
            modifiedAt: t(5),
          ),
        ),
        equals(
          TdfPayloadComparison.labelPayloadSignature(
            TdfLabel(
              id: 'lblSig0001',
              name: 'Ops',
              color: '#AABBCC',
              modifiedAt: t(50),
            ),
          ),
        ),
      );
      expect(
        TdfPayloadComparison.locationPayloadSignature(
          TdfLocation(
            id: 'locSig0001',
            name: 'HQ',
            latitude: 48.1,
            longitude: 11.5,
            radius: 100,
            rawRadiusText: '100.00',
            modifiedAt: t(5),
          ),
        ),
        equals(
          TdfPayloadComparison.locationPayloadSignature(
            TdfLocation(
              id: 'locSig0001',
              name: 'HQ',
              latitude: 48.1,
              longitude: 11.5,
              radius: 100,
              rawRadiusText: '100',
              modifiedAt: t(50),
            ),
          ),
        ),
      );

      // Equal-timestamp tie-break on dueAnchor in both (L, R) and (R, L):
      final tieLeft = evalBoard(<TaskItem>[withAnchorEarlyMod10]);
      final tieRight = evalBoard(<TaskItem>[withAnchorLateMod10]);
      for (final (first, second) in <(TaskBoard, TaskBoard)>[
        (tieLeft, tieRight),
        (tieRight, tieLeft),
      ]) {
        final mergedTie = syncBoards(first, second);
        final winnerTask = mergedTie.findTask(id)!;
        expect(
          winnerTask.dueAnchor,
          equals(anchorLate),
          reason:
              'Greater dueAnchor must win equal-timestamp tie symmetrically',
        );
        expect(winnerTask.modifiedAt, equals(t(10)));
      }

      // Case 2 same-occurrence merge preserves dueAnchor atomically & preserves G.modifiedAt (including null) when M_clean == G:
      final rawNoModWithAnchor = TaskItem(
        id: id,
        title: 'Unmodified Anchor',
        createdAt: defaultCreated,
        dueAt: dueUtc,
        dueAnchor: anchorLate,
      );
      final idempotentBoard = evalBoard(<TaskItem>[rawNoModWithAnchor]);
      final idempotentMerged = syncBoards(
        idempotentBoard,
        idempotentBoard,
        idempotentBoard,
      );
      expect(idempotentMerged.findTask(id)!.dueAnchor, equals(anchorLate));
      expect(
        idempotentMerged.findTask(id)!.modifiedAt,
        isNull,
        reason: 'Idempotent Case 2 merge with dueAnchor must preserve omitted modifiedAt',
      );

      // Case 2 concurrent title edit on L + anchor-only edit on R -> keeps both and advances revision to max + 1s:
      final case2Base = evalBoard(<TaskItem>[withAnchorEarlyMod10]);
      final case2Local = evalBoard(<TaskItem>[
        withAnchorEarlyMod10.copyWith(
          title: 'Renamed Report',
          modifiedAt: t(14),
        ),
      ]);
      final case2Remote = evalBoard(<TaskItem>[
        withAnchorEarlyMod10.copyWith(dueAnchor: anchorLate, modifiedAt: t(12)),
      ]);
      final case2Merged = syncBoards(
        case2Local,
        case2Remote,
        case2Base,
        t(100),
      );
      final case2Task = case2Merged.findTask(id)!;
      expect(case2Task.title, equals('Renamed Report'));
      expect(case2Task.dueAnchor, equals(anchorLate));
      expect(
        case2Task.modifiedAt,
        equals(t(15)),
        reason: 'Clock-free Case 2 merge without block cleanup must advance to max(10,14,12) + 1s',
      );

      // Case 1 cross-occurrence merge copies dueAnchor atomically from occurrence winner:
      final case1Remote = evalBoard(<TaskItem>[
        withAnchorEarlyMod10.copyWith(
          completions: 1,
          dueAt: DateTime.utc(2026, 3, 31, 16, 0, 0),
          dueAnchor: TdfLocalDateTime(2026, 3, 31, 18, 0, 0),
          modifiedAt: t(11),
        ),
      ]);
      final case1Merged = syncBoards(
        case2Local,
        case1Remote,
        case2Base,
        t(100),
      );
      final case1Task = case1Merged.findTask(id)!;
      expect(case1Task.completions, equals(1));
      expect(case1Task.title, equals('Renamed Report'));
      expect(
        case1Task.dueAnchor,
        equals(TdfLocalDateTime(2026, 3, 31, 18, 0, 0)),
        reason: 'Case 1 occurrence winner must carry its dueAnchor atomically',
      );

      // DeletionConflict screening on anchor-only edit relative to B:
      final remoteDeleted = evalBoard(
        const <TaskItem>[],
        null,
        20,
        null,
        const <TdfLabel>[],
        TdfDeletedBlock(
          generation: 0,
          tasks: <TdfDeletedTaskRecord>[
            TdfDeletedTaskRecord(taskId: id, deletedAt: t(20)),
          ],
        ),
      );
      expect(
        () => syncBoards(case2Remote, remoteDeleted, case2Base, t(100)),
        throwsSyncOutcome(
          TdfSyncOutcomeKind.deletionConflict,
          conflictedTasks: contains(id),
        ),
        reason: 'Anchor-only edit vs remote tombstone must trigger DeletionConflict',
      );
    });

    test('enforces TdfCleanupMode.deferred vs finalStage multi-stage fairness without wall-clock revision inflation', () {
      const id = 'fair000001';
      final t10 = t(10);
      final t11 = t(11);
      final t12 = t(12);
      final t50 = t(50);
      final t100 = t(100);

      final taskB = TaskItem(
        id: id,
        title: 'A',
        createdAt: defaultCreated,
        modifiedAt: t10,
        suspendedAt: t50,
        suspendedNote: 'Deferred until T50',
      );
      final taskL = taskB.copyWith(title: 'Z', modifiedAt: t11);
      final taskR = taskB.copyWith(title: 'Y', modifiedAt: t12);

      final boardB = TaskBoard.evaluate(
        tasks: <TaskItem>[taskB],
        evaluationTime: t10,
      );
      final boardL = TaskBoard.evaluate(
        tasks: <TaskItem>[taskL],
        evaluationTime: t11,
      );
      final boardR = TaskBoard.evaluate(
        tasks: <TaskItem>[taskR],
        evaluationTime: t12,
      );

      // Direct single-stage final merge(B, L, R) at now = T100:
      final directFinal = TaskBoardSync.merge(
        primary: boardL,
        secondary: boardR,
        baseline: boardB,
        evaluationTime: t100,
        cleanupMode: TdfCleanupMode.finalStage,
      );
      expect(directFinal.findTask(id)!.title, equals('Y'));
      expect(directFinal.findTask(id)!.suspendedAt, isNull);
      expect(directFinal.findTask(id)!.modifiedAt, equals(t100));

      // Multi-stage sync: Stage 1 runs in TdfCleanupMode.deferred at now = T100!
      // Even when localDisk also edited note at T10 (forcing a 3-way merge revision bump in Stage 1),
      // deferred mode must keep suspended = T50 and assign clock-free max(T10, T11, T10) + 1s? Wait:
      // First test exact spec vector: Stage 1 merges (B, L, B) at now = T100 in deferred mode -> keeps T11!
      final stage1Exact = TaskBoardSync.merge(
        primary: boardL,
        secondary: boardB,
        baseline: boardB,
        evaluationTime: t100,
        cleanupMode: TdfCleanupMode.deferred,
      );
      final stage1Task = stage1Exact.findTask(id)!;
      expect(stage1Task.title, equals('Z'));
      expect(
        stage1Task.suspendedAt,
        equals(t50),
        reason:
            'TdfCleanupMode.deferred must preserve expired suspended <= now',
      );
      expect(
        stage1Task.modifiedAt,
        equals(t11),
        reason: 'TdfCleanupMode.deferred must preserve T11 without inflating to T100',
      );

      final stage2Final = TaskBoardSync.merge(
        primary: stage1Exact,
        secondary: boardR,
        baseline: boardB,
        evaluationTime: t100,
        cleanupMode: TdfCleanupMode.finalStage,
      );
      final stage2Task = stage2Final.findTask(id)!;
      expect(
        stage2Task.title,
        equals('Y'),
        reason: 'Remote T12 edit must beat Stage 1 T11 identically to direct merge(B, L, R)',
      );
      expect(stage2Task.suspendedAt, isNull);
      expect(stage2Task.suspendedNote, isNull);
      expect(stage2Task.modifiedAt, equals(t100));

      // Also verify clock-free +1s in TdfCleanupMode.deferred when 3-way units diverge while suspended <= now:
      final boardDiskNote = TaskBoard.evaluate(
        tasks: <TaskItem>[taskB.copyWith(note: 'Disk Note', modifiedAt: t10)],
        evaluationTime: t10,
      );
      final stage1ThreeWay = TaskBoardSync.merge(
        primary: TaskBoard.evaluate(
          tasks: <TaskItem>[taskB.copyWith(title: 'Z', modifiedAt: t10)],
          evaluationTime: t10,
        ),
        secondary: boardDiskNote,
        baseline: boardB,
        evaluationTime: t100,
        cleanupMode: TdfCleanupMode.deferred,
      );
      expect(stage1ThreeWay.findTask(id)!.suspendedAt, equals(t50));
      expect(
        stage1ThreeWay.findTask(id)!.modifiedAt,
        equals(t11),
        reason: 'Deferred 3-way merge must advance to max(T10,T10,T10)+1s=T11 without reading wall-clock T100',
      );

      // Verify stampAndNormalize cleanupMode parameter:
      final stampedDeferred = TaskBoardSync.stampAndNormalize(
        boardL,
        evaluationTime: t100,
        cleanupMode: TdfCleanupMode.deferred,
      );
      expect(stampedDeferred.findTask(id)!.suspendedAt, equals(t50));
      expect(stampedDeferred.findTask(id)!.modifiedAt, equals(t11));
    });

    test('runs symmetric Phase 1 generation refresh when primary.generation > secondary.generation without false rollback and strips discarded blocked refs', () {
      const retiredId = 'ret0000001';
      const sharedOpenId = 'opn0000001';
      const sharedDoneId = 'don0000001';
      const staleEditedId = 'edt0000002';
      const staleNewId = 'new0000002';
      const unackedDelId = 'und0000001';
      const ackedDelId = 'ack0000001';

      final retiredBase = makeTask(retiredId, 'Retired Cached Task', 10);
      final unackedLiveBase = makeTask(
        unackedDelId,
        'Deleted Locally On Disk',
        10,
      );
      final openBase = makeTask(
        sharedOpenId,
        'Open Dependent',
        10,
        0,
        const <String>[],
        const <TdfTaskDependency>[
          TdfTaskDependency(taskId: retiredId, requiredCompletion: 1),
        ],
      );
      final doneBase = TaskItem(
        id: sharedDoneId,
        title: 'Completed Dependent',
        createdAt: defaultCreated,
        completedAt: t(10),
        isCompleted: true,
        completions: 1,
        modifiedAt: t(10),
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: retiredId, requiredCompletion: 1),
        ],
      );

      final baselineAtG = TaskBoard.evaluate(
        tasks: <TaskItem>[retiredBase, unackedLiveBase, openBase, doneBase],
        deletedBlock: TdfDeletedBlock(
          generation: 1,
          tasks: <TdfDeletedTaskRecord>[
            TdfDeletedTaskRecord(taskId: ackedDelId, deletedAt: t(5)),
          ],
        ),
        evaluationTime: t(10),
      );

      // Primary (loopL after Stage 2 remote 30-day prune) is at generation g + 1 = 2:
      // ackedDelId and retiredId already expired; unackedLiveBase is still live on loopL; openBase was cleaned or edited.
      final primaryAdvanced = TaskBoard.evaluate(
        tasks: <TaskItem>[
          unackedLiveBase,
          openBase.copyWith(title: 'Open Dependent Remote', modifiedAt: t(15)),
          doneBase,
        ],
        deletedBlock: TdfDeletedBlock(generation: 2),
        evaluationTime: t(20),
      );

      // Secondary (external local disk R) is still at generation g = 1 == acknowledgedLocalGeneration:
      // retains unchanged retiredBase, deleted unackedLiveBase (unacknowledged tombstone), and kept ackedDelId!
      final secondaryStaleClean = TaskBoard.evaluate(
        tasks: <TaskItem>[retiredBase, openBase, doneBase],
        deletedBlock: TdfDeletedBlock(
          generation: 1,
          tasks: <TdfDeletedTaskRecord>[
            TdfDeletedTaskRecord(taskId: ackedDelId, deletedAt: t(5)),
            TdfDeletedTaskRecord(taskId: unackedDelId, deletedAt: t(18)),
          ],
        ),
        evaluationTime: t(20),
      );

      final converged = TaskBoardSync.merge(
        primary: primaryAdvanced,
        secondary: secondaryStaleClean,
        baseline: baselineAtG,
        acknowledgedGeneration: 1,
        evaluationTime: t(30),
        cleanupMode: TdfCleanupMode.finalStage,
      );
      expect(
        converged.deletedBlock.generation,
        equals(2),
        reason:
            'Must adopt max(g+1, g) = 2 without false SyncGenerationRollback',
      );
      expect(
        converged.findTask(retiredId),
        isNull,
        reason: 'Unchanged cached entity on stale secondary must be discarded silently',
      );
      expect(
        converged.deletedBlock.findTaskRecord(retiredId),
        isNull,
        reason: 'Discarded stale cached entity must not synthesize a fresh tombstone',
      );
      expect(
        converged.deletedBlock.findTaskRecord(ackedDelId),
        isNull,
        reason: 'Superseded acknowledged tombstone on stale secondary must be discarded',
      );
      expect(
        converged.findTask(unackedDelId),
        isNull,
        reason: 'Unacknowledged tombstone on stale secondary must delete unchanged primary entity',
      );
      expect(
        converged.deletedBlock.findTaskRecord(unackedDelId)?.deletedAt,
        equals(t(18)),
      );
      expect(
        converged.findTask(sharedOpenId)!.dependencies,
        isEmpty,
        reason: 'TDF-REC-002 must strip blocked reference targeting auto-discarded retiredId on open tasks',
      );
      expect(
        converged.findTask(sharedOpenId)!.modifiedAt,
        equals(t(30)),
        reason: 'Stripping discarded blocked ref on open task advances modified via TDF-MUT-002',
      );
      expect(
        converged.findTask(sharedDoneId)!.dependencies,
        isNotEmpty,
        reason: 'TDF-REC-002 only strips discarded refs from live open tasks, leaving Completed tasks untouched',
      );

      // If stale secondary modified a retired cached task OR added an unacknowledged task -> RecoveryRequired!
      final secondaryStaleAmbiguous = TaskBoard.evaluate(
        tasks: <TaskItem>[
          retiredBase.copyWith(
            dueAt: t(500),
            dueAnchor: TdfLocalDateTime(2026, 11, 30, 12, 0, 0),
            modifiedAt: t(16),
          ),
          makeTask(staleEditedId, 'Not in B', 17),
          makeTask(staleNewId, 'Also Not in B', 18),
          openBase,
        ],
        deletedBlock: TdfDeletedBlock(generation: 1),
        evaluationTime: t(20),
      );
      expect(
        () => TaskBoardSync.merge(
          primary: primaryAdvanced,
          secondary: secondaryStaleAmbiguous,
          baseline: baselineAtG,
          acknowledgedGeneration: 1,
          evaluationTime: t(30),
        ),
        throwsSyncOutcome(
          TdfSyncOutcomeKind.recoveryRequired,
          ambiguousTasks: containsAll(<String>[
            retiredId,
            staleEditedId,
            staleNewId,
          ]),
        ),
      );
    });

    test('reconstructs pre-cascade L_before(T) and enforces commutative scoped label deletion flood protection', () {
      const scopedId = 'scp0000001';
      const taskScopedId = 'tskScp0001';
      const scopedLabel = TdfLabel(
        id: scopedId,
        name: 'Private',
        isScoped: true,
      );
      final anchor = TdfLocalDateTime(2026, 1, 31, 18, 0, 0);
      final dueUtc = DateTime.utc(2026, 2, 28, 17, 0, 0);
      final historyEntries = <TaskHistoryEntry>[
        TaskHistoryEntry(timestampUtc: t(5), text: 'Created note'),
      ];

      final baseTask = TaskItem(
        id: taskScopedId,
        title: 'Scoped Someday Task',
        createdAt: defaultCreated,
        modifiedAt: t(10),
        labelIds: const <String>[scopedId],
        dueAt: dueUtc,
        dueAnchor: anchor,
        isDuePassive: true,
        dueNote: 'Keep deadline',
        origin: const TaskOrigin(namespace: 'jira', externalKey: 'OPS-42'),
        history: historyEntries,
      );
      final boardB = TaskBoard.evaluate(
        tasks: <TaskItem>[baseTask],
        labels: const <TdfLabel>[scopedLabel],
        queueBlock: makeQueue(10, const <String>[]),
        evaluationTime: t(10),
      );

      // Side A deletes scopedLabel (cascading labels -> [] on taskScopedId at t(20)):
      final boardDeletedScoped = TaskBoard.evaluate(
        tasks: <TaskItem>[
          baseTask.copyWith(labelIds: const <String>[], modifiedAt: t(20)),
        ],
        labels: const <TdfLabel>[],
        deletedBlock: TdfDeletedBlock(
          generation: 0,
          labels: <TdfDeletedLabelRecord>[
            TdfDeletedLabelRecord(labelId: scopedId, deletedAt: t(20)),
          ],
        ),
        queueBlock: makeQueue(10, const <String>[]),
        evaluationTime: t(20),
      );

      // Side B concurrently promotes taskScopedId to Focus (isPriority = true, in queue) while still carrying scopedLabel:
      final boardScheduledScoped = TaskBoard.evaluate(
        tasks: <TaskItem>[
          baseTask.copyWith(
            isPriority: true,
            isDuePassive: false,
            modifiedAt: t(15),
          ),
        ],
        labels: const <TdfLabel>[scopedLabel],
        queueBlock: makeQueue(15, const <String>[taskScopedId]),
        evaluationTime: t(15),
      );

      final mergedLR = TaskBoardSync.merge(
        primary: boardDeletedScoped,
        secondary: boardScheduledScoped,
        baseline: boardB,
        evaluationTime: t(30),
      );
      final mergedRL = TaskBoardSync.merge(
        primary: boardScheduledScoped,
        secondary: boardDeletedScoped,
        baseline: boardB,
        evaluationTime: t(30),
      );

      for (final merged in <TaskBoard>[mergedLR, mergedRL]) {
        final resultTask = merged.findTask(taskScopedId)!;
        expect(resultTask.labelIds, isEmpty);
        expect(
          resultTask.isPriority,
          isFalse,
          reason: 'Scoped flood protection must strip priority symmetrically',
        );
        expect(
          merged.queueBlock.taskIds,
          isNot(contains(taskScopedId)),
          reason: 'Scoped flood protection must evict task from queue symmetrically',
        );
        expect(merged.someday.map((item) => item.id), contains(taskScopedId));
        expect(resultTask.dueAt, equals(dueUtc));
        expect(resultTask.dueAnchor, equals(anchor));
        expect(resultTask.dueNote, equals('Keep deadline'));
        expect(
          resultTask.origin,
          equals(const TaskOrigin(namespace: 'jira', externalKey: 'OPS-42')),
        );
        expect(resultTask.history, equals(historyEntries));
      }
      expect(
        mergedLR.findTask(taskScopedId),
        equals(mergedRL.findTask(taskScopedId)),
        reason:
            'merge(B, L, R) and merge(B, R, L) must produce identical TaskItem',
      );
      expect(
        mergedLR.queueBlock,
        equals(mergedRL.queueBlock),
        reason: 'merge(B, L, R) and merge(B, R, L) must produce identical queueBlock',
      );

      // Exception check: if Side A deleted scopedLabel AND intentionally scheduled the unlabelled task in queue,
      // it MUST NOT be scoped-evicted!
      final boardAlreadyUnlabelledQueued = TaskBoard.evaluate(
        tasks: <TaskItem>[
          baseTask.copyWith(
            labelIds: const <String>[],
            isPriority: true,
            modifiedAt: t(22),
          ),
        ],
        labels: const <TdfLabel>[],
        deletedBlock: TdfDeletedBlock(
          generation: 0,
          labels: <TdfDeletedLabelRecord>[
            TdfDeletedLabelRecord(labelId: scopedId, deletedAt: t(20)),
          ],
        ),
        queueBlock: makeQueue(22, const <String>[taskScopedId]),
        evaluationTime: t(22),
      );
      for (final (first, second) in <(TaskBoard, TaskBoard)>[
        (boardAlreadyUnlabelledQueued, boardB),
        (boardB, boardAlreadyUnlabelledQueued),
      ]) {
        final preservedQueued = TaskBoardSync.merge(
          primary: first,
          secondary: second,
          baseline: boardB,
          evaluationTime: t(30),
        );
        expect(
          preservedQueued.queueBlock.taskIds,
          contains(taskScopedId),
          reason: 'Task already queued with empty labels on an input side must not be scoped-evicted',
        );
        expect(preservedQueued.findTask(taskScopedId)!.isPriority, isTrue);
      }
    });

    test('verifies TdfBoundDeletionDecision across tasks, labels, and locations and rejects stale bound decisions', () {
      const taskId = 'bndTsk0001';
      const labelId = 'bndLbl0001';
      const locId = 'bndLoc0001';

      final anchor1 = TdfLocalDateTime(2026, 1, 31, 12, 0, 0);
      final anchor2 = TdfLocalDateTime(2026, 1, 31, 13, 0, 0);
      final baseTask = TaskItem(
        id: taskId,
        title: 'Bound Task',
        createdAt: defaultCreated,
        modifiedAt: t(10),
        dueAt: t(500),
        dueAnchor: anchor1,
      );
      final baseLabel = TdfLabel(
        id: labelId,
        name: 'Bound Label',
        modifiedAt: t(10),
      );
      final baseLoc = TdfLocation(
        id: locId,
        name: 'Bound Location',
        latitude: 48.1,
        longitude: 11.5,
        radius: 100,
        modifiedAt: t(10),
      );

      final boardB = TaskBoard.evaluate(
        tasks: <TaskItem>[baseTask],
        labels: <TdfLabel>[baseLabel],
        locations: <TdfLocation>[baseLoc],
        queueBlock: makeQueue(10, const <String>[taskId]),
        evaluationTime: t(10),
      );

      final editedTask = baseTask.copyWith(
        title: 'Bound Task Edited',
        modifiedAt: t(15),
      );
      final editedLabel = baseLabel.copyWith(
        name: 'Bound Label Edited',
        modifiedAt: t(15),
      );
      final editedLoc = baseLoc.copyWith(
        name: 'Bound Location Edited',
        modifiedAt: t(15),
      );
      final boardLive = TaskBoard.evaluate(
        tasks: <TaskItem>[editedTask],
        labels: <TdfLabel>[editedLabel],
        locations: <TdfLocation>[editedLoc],
        queueBlock: makeQueue(15, const <String>[taskId]),
        evaluationTime: t(15),
      );

      final boardDeleted = TaskBoard.evaluate(
        tasks: const <TaskItem>[],
        labels: const <TdfLabel>[],
        locations: const <TdfLocation>[],
        deletedBlock: TdfDeletedBlock(
          generation: 0,
          tasks: <TdfDeletedTaskRecord>[
            TdfDeletedTaskRecord(taskId: taskId, deletedAt: t(20)),
          ],
          labels: <TdfDeletedLabelRecord>[
            TdfDeletedLabelRecord(labelId: labelId, deletedAt: t(20)),
          ],
          locations: <TdfDeletedLocationRecord>[
            TdfDeletedLocationRecord(locationId: locId, deletedAt: t(20)),
          ],
        ),
        evaluationTime: t(20),
      );

      final validTaskDecision = TdfBoundDeletionDecision(
        resolution: TdfDeletionResolution.undelete,
        expectedLiveModifiedAt: t(15),
        expectedDeletionAt: t(20),
        expectedLivePayloadSignature: TdfPayloadComparison.taskPayloadSignature(
          editedTask,
        ),
      );
      final validLabelDecision = TdfBoundDeletionDecision(
        resolution: TdfDeletionResolution.undelete,
        expectedLiveModifiedAt: t(15),
        expectedDeletionAt: t(20),
        expectedLivePayloadSignature:
            TdfPayloadComparison.labelPayloadSignature(editedLabel),
      );
      final validLocDecision = TdfBoundDeletionDecision(
        resolution: TdfDeletionResolution.delete,
        expectedLiveModifiedAt: t(15),
        expectedDeletionAt: t(20),
        expectedLivePayloadSignature:
            TdfPayloadComparison.locationPayloadSignature(editedLoc),
      );

      final resolved = TaskBoardSync.merge(
        primary: boardLive,
        secondary: boardDeleted,
        baseline: boardB,
        boundTaskConflictDecisions: <String, TdfBoundDeletionDecision>{
          taskId: validTaskDecision,
        },
        boundLabelConflictDecisions: <String, TdfBoundDeletionDecision>{
          labelId: validLabelDecision,
        },
        boundLocationConflictDecisions: <String, TdfBoundDeletionDecision>{
          locId: validLocDecision,
        },
        evaluationTime: t(30),
      );
      expect(resolved.findTask(taskId)?.title, equals('Bound Task Edited'));
      expect(resolved.findLabel(labelId)?.name, equals('Bound Label Edited'));
      expect(resolved.findLocation(locId), isNull);
      expect(resolved.deletedBlock.generation, equals(1));
      expect(resolved.queueBlock.taskIds, contains(taskId));

      // 1. Anchor-only mutation on live task invalidates expectedLivePayloadSignature -> re-throws DeletionConflict!
      final anchorChangedBoard = TaskBoard.evaluate(
        tasks: <TaskItem>[editedTask.copyWith(dueAnchor: anchor2)],
        labels: <TdfLabel>[editedLabel],
        locations: <TdfLocation>[editedLoc],
        queueBlock: makeQueue(15, const <String>[taskId]),
        evaluationTime: t(15),
      );
      expect(
        () => TaskBoardSync.merge(
          primary: anchorChangedBoard,
          secondary: boardDeleted,
          baseline: boardB,
          boundTaskConflictDecisions: <String, TdfBoundDeletionDecision>{
            taskId: validTaskDecision,
          },
          boundLabelConflictDecisions: <String, TdfBoundDeletionDecision>{
            labelId: validLabelDecision,
          },
          boundLocationConflictDecisions: <String, TdfBoundDeletionDecision>{
            locId: validLocDecision,
          },
          evaluationTime: t(30),
        ),
        throwsSyncOutcome(
          TdfSyncOutcomeKind.deletionConflict,
          conflictedTasks: contains(taskId),
        ),
        reason: 'Anchor-only change on live task must invalidate bound decision signature',
      );

      // 2. Live modifiedAt mismatch -> re-throws DeletionConflict!
      expect(
        () => TaskBoardSync.merge(
          primary: boardLive,
          secondary: boardDeleted,
          baseline: boardB,
          boundTaskConflictDecisions: <String, TdfBoundDeletionDecision>{
            taskId: TdfBoundDeletionDecision(
              resolution: TdfDeletionResolution.delete,
              expectedLiveModifiedAt: t(14),
            ),
          },
          boundLabelConflictDecisions: <String, TdfBoundDeletionDecision>{
            labelId: validLabelDecision,
          },
          boundLocationConflictDecisions: <String, TdfBoundDeletionDecision>{
            locId: validLocDecision,
          },
          evaluationTime: t(30),
        ),
        throwsSyncOutcome(
          TdfSyncOutcomeKind.deletionConflict,
          conflictedTasks: contains(taskId),
        ),
      );

      // 3. Deletion timestamp mismatch -> re-throws DeletionConflict!
      expect(
        () => TaskBoardSync.merge(
          primary: boardLive,
          secondary: boardDeleted,
          baseline: boardB,
          boundTaskConflictDecisions: <String, TdfBoundDeletionDecision>{
            taskId: TdfBoundDeletionDecision(
              resolution: TdfDeletionResolution.delete,
              expectedDeletionAt: t(19),
            ),
          },
          boundLabelConflictDecisions: <String, TdfBoundDeletionDecision>{
            labelId: validLabelDecision,
          },
          boundLocationConflictDecisions: <String, TdfBoundDeletionDecision>{
            locId: validLocDecision,
          },
          evaluationTime: t(30),
        ),
        throwsSyncOutcome(
          TdfSyncOutcomeKind.deletionConflict,
          conflictedTasks: contains(taskId),
        ),
      );
    });

    test('resolves RecoveryRequired with TdfRecoveryResolution.discard and recoverAsNew across tasks, labels, and locations', () {
      const keepTaskId = 'recKeepTsk';
      const dropTaskId = 'recDropTsk';
      const keepLabelId = 'recKeepLbl';
      const dropScopedLabelId = 'recDropLbl';
      const keepLocId = 'recKeepLoc';
      const dropLocId = 'recDropLoc';
      const sharedOpenId = 'shrOpenTsk';

      final anchor = TdfLocalDateTime(2026, 1, 31, 18, 0, 0);
      final dueUtc = DateTime.utc(2026, 2, 28, 17, 0, 0);
      final hist = <TaskHistoryEntry>[
        TaskHistoryEntry(timestampUtc: t(8), text: 'Progress entry'),
      ];

      final sharedOnRemote = makeTask(
        sharedOpenId,
        'Shared Open Task',
        10,
        0,
        const <String>[],
        const <TdfTaskDependency>[
          TdfTaskDependency(taskId: dropTaskId, requiredCompletion: 1),
        ],
      );
      final sharedBoard = TaskBoard.evaluate(
        tasks: <TaskItem>[sharedOnRemote],
        deletedBlock: TdfDeletedBlock(generation: 2),
        queueBlock: makeQueue(10, const <String>[sharedOpenId]),
        evaluationTime: t(20),
      );

      final keepTask = TaskItem(
        id: keepTaskId,
        title: 'Recovered Task With Anchor & History',
        createdAt: defaultCreated,
        modifiedAt: t(12),
        dueAt: dueUtc,
        dueAnchor: anchor,
        dueNote: 'Month-end',
        history: hist,
        labelIds: const <String>[keepLabelId, dropScopedLabelId],
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: dropTaskId, requiredCompletion: 1),
        ],
        conditions: const <TaskCondition>[
          LocationTaskCondition(locationIds: <String>[keepLocId, dropLocId]),
        ],
      );
      final dropTask = makeTask(
        dropTaskId,
        'Discarded Task',
        12,
        0,
        const <String>[dropScopedLabelId],
      );

      final localBoard = TaskBoard.evaluate(
        tasks: <TaskItem>[
          keepTask,
          dropTask,
          sharedOnRemote.copyWith(
            labelIds: const <String>[keepLabelId, dropScopedLabelId],
            dependencies: const <TdfTaskDependency>[
              TdfTaskDependency(taskId: keepTaskId, requiredCompletion: 1),
              TdfTaskDependency(taskId: dropTaskId, requiredCompletion: 1),
            ],
            conditions: const <TaskCondition>[
              LocationTaskCondition(locationIds: <String>[dropLocId]),
            ],
            modifiedAt: t(14),
          ),
        ],
        labels: <TdfLabel>[
          TdfLabel(
            id: keepLabelId,
            name: 'Recovered Label',
            conditions: const <TaskCondition>[
              LocationTaskCondition(
                locationIds: <String>[keepLocId, dropLocId],
              ),
            ],
            modifiedAt: t(12),
          ),
          TdfLabel(
            id: dropScopedLabelId,
            name: 'Discarded Scoped Label',
            isScoped: true,
            modifiedAt: t(12),
          ),
        ],
        locations: <TdfLocation>[
          TdfLocation(
            id: keepLocId,
            name: 'Recovered Location',
            latitude: 48.1,
            longitude: 11.5,
            radius: 100,
            modifiedAt: t(12),
          ),
          TdfLocation(
            id: dropLocId,
            name: 'Discarded Location',
            latitude: 48.2,
            longitude: 11.6,
            radius: 200,
            modifiedAt: t(12),
          ),
        ],
        deletedBlock: TdfDeletedBlock(generation: 1),
        queueBlock: makeQueue(14, const <String>[
          sharedOpenId,
          keepTaskId,
          dropTaskId,
        ]),
        evaluationTime: t(20),
      );

      final recovered = TaskBoardSync.recoverAmbiguousEntities(
        localBoard: localBoard,
        sharedBoard: sharedBoard,
        taskRecoveryResolutions: const <String, TdfRecoveryResolution>{
          keepTaskId: TdfRecoveryResolution.recoverAsNew,
          dropTaskId: TdfRecoveryResolution.discard,
        },
        labelRecoveryResolutions: const <String, TdfRecoveryResolution>{
          keepLabelId: TdfRecoveryResolution.recoverAsNew,
          dropScopedLabelId: TdfRecoveryResolution.discard,
        },
        locationRecoveryResolutions: const <String, TdfRecoveryResolution>{
          keepLocId: TdfRecoveryResolution.recoverAsNew,
          dropLocId: TdfRecoveryResolution.discard,
        },
        evaluationTime: t(30),
      );

      expect(recovered.deletedBlock.generation, equals(2));
      expect(recovered.findTask(dropTaskId), isNull);
      expect(recovered.findLabel(dropScopedLabelId), isNull);
      expect(recovered.findLocation(dropLocId), isNull);

      expect(recovered.locations.length, equals(1));
      final newLocId = recovered.locations.single.id;
      expect(newLocId, isNot(equals(keepLocId)));

      expect(recovered.labels.length, equals(1));
      final newLabel = recovered.labels.single;
      expect(newLabel.id, isNot(equals(keepLabelId)));
      expect(
        (newLabel.conditions.single as LocationTaskCondition).locationIds,
        equals(<String>[newLocId]),
        reason: 'Recovered label must rewrite kept location ID and strip discarded location ID',
      );

      final recTask = recovered.allTasks.firstWhere(
        (task) => task.id != sharedOpenId,
      );
      expect(recTask.id, isNot(equals(keepTaskId)));
      expect(recTask.dueAnchor, equals(anchor));
      expect(recTask.history, equals(hist));
      expect(recTask.labelIds, equals(<String>[newLabel.id]));
      expect(
        recTask.dependencies,
        isEmpty,
        reason: 'Recovered open task must strip discarded prerequisite',
      );
      expect(
        (recTask.conditions.single as LocationTaskCondition).locationIds,
        equals(<String>[newLocId]),
      );
      expect(
        recovered.queueBlock.taskIds,
        containsAllInOrder(<String>[sharedOpenId, recTask.id]),
        reason: 'Recovered open queued task must be preserved in queue under its fresh ID',
      );

      final sharedAfter = recovered.findTask(sharedOpenId)!;
      expect(sharedAfter.labelIds, equals(<String>[newLabel.id]));
      expect(
        sharedAfter.dependencies,
        equals(<TdfTaskDependency>[
          TdfTaskDependency(taskId: recTask.id, requiredCompletion: 1),
        ]),
        reason: 'Shared open task must rewrite recovered prerequisite and strip discarded prerequisite',
      );
      expect(
        sharedAfter.conditions,
        equals(const <TaskCondition>[
          GroupResetTaskCondition(targetGroup: ConditionGroup.location),
        ]),
        reason: 'Emptying shared task location condition while assigned label still has location rule must insert location any',
      );
    });

    test('enforces maxTdfSyncGeneration overflow, baseline-free L_before(T), Completed retention gating by cleanupMode, and inline merge recoveryResolutions', () {
      // 1. maxTdfSyncGeneration accepted when no records retire, and throws limitExceeded on tombstone expiry:
      final delTime = DateTime.utc(2026, 10, 1, 12, 0, 0);
      final within30Days = delTime.add(const Duration(seconds: 2592000));
      final past30Days = delTime.add(const Duration(seconds: 2592001));
      final atMaxGen = TaskBoard.evaluate(
        tasks: const <TaskItem>[],
        deletedBlock: TdfDeletedBlock(
          generation: maxTdfSyncGeneration,
          tasks: <TdfDeletedTaskRecord>[
            TdfDeletedTaskRecord(taskId: 'delMaxGen1', deletedAt: delTime),
          ],
        ),
        evaluationTime: within30Days,
      );
      final preservedMaxGen = TaskBoardSync.merge(
        primary: atMaxGen,
        secondary: atMaxGen,
        baseline: atMaxGen,
        evaluationTime: within30Days,
      );
      expect(
        preservedMaxGen.deletedBlock.generation,
        equals(maxTdfSyncGeneration),
      );

      expect(
        () => TaskBoardSync.merge(
          primary: atMaxGen,
          secondary: atMaxGen,
          baseline: atMaxGen,
          evaluationTime: past30Days,
        ),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason: 'Advancing past MAX_SYNC_GENERATION must throw limitExceeded',
      );

      // 2. Completed > 30 days retained in TdfCleanupMode.deferred and garbage-collected in finalStage without generation increment:
      const doneId = 'cmpPrn0001';
      final doneTask = TaskItem(
        id: doneId,
        title: 'Old Completed Task',
        createdAt: delTime,
        completedAt: delTime,
        isCompleted: true,
        completions: 3,
        modifiedAt: delTime,
      );
      final boardWithOldDone = TaskBoard.evaluate(
        tasks: <TaskItem>[doneTask],
        evaluationTime: within30Days,
      );
      final deferredDone = TaskBoardSync.merge(
        primary: boardWithOldDone,
        secondary: boardWithOldDone,
        baseline: boardWithOldDone,
        evaluationTime: past30Days,
        cleanupMode: TdfCleanupMode.deferred,
      );
      expect(
        deferredDone.findTask(doneId),
        isNotNull,
        reason: 'Deferred stage must not garbage-collect >30d Completed tasks',
      );
      final finalDone = TaskBoardSync.merge(
        primary: boardWithOldDone,
        secondary: boardWithOldDone,
        baseline: boardWithOldDone,
        evaluationTime: past30Days,
        cleanupMode: TdfCleanupMode.finalStage,
      );
      expect(finalDone.findTask(doneId), isNull);
      expect(finalDone.deletedBlock.generation, equals(0));
      expect(
        finalDone.deletedBlock.findTaskRecord(doneId)?.completionsCheckpoint,
        equals(3),
      );
      expect(
        finalDone.deletedBlock.findTaskRecord(doneId)?.deletedAt,
        equals(past30Days),
      );

      // 3. Baseline-free L_before(T) = W.labels U (Loser.labels intersect (D_label_W \ D_label_Loser)):
      const scopedId = 'scpNoBase1';
      const taskNoBaseId = 'tskNoBase1';
      const scopedLbl = TdfLabel(id: scopedId, name: 'Scoped', isScoped: true);
      final winnerDeletedBoard = TaskBoard.evaluate(
        tasks: <TaskItem>[makeTask(taskNoBaseId, 'No Base Scoped', 25)],
        labels: const <TdfLabel>[],
        deletedBlock: TdfDeletedBlock(
          generation: 0,
          labels: <TdfDeletedLabelRecord>[
            TdfDeletedLabelRecord(labelId: scopedId, deletedAt: t(25)),
          ],
        ),
        queueBlock: makeQueue(10, const <String>[]),
        evaluationTime: t(25),
      );
      final loserScheduledBoard = TaskBoard.evaluate(
        tasks: <TaskItem>[
          makeTask(taskNoBaseId, 'No Base Scoped', 15, 0, const <String>[
            scopedId,
          ]).copyWith(isPriority: true),
        ],
        labels: const <TdfLabel>[scopedLbl],
        queueBlock: makeQueue(15, const <String>[taskNoBaseId]),
        evaluationTime: t(15),
      );
      for (final (first, second) in <(TaskBoard, TaskBoard)>[
        (winnerDeletedBoard, loserScheduledBoard),
        (loserScheduledBoard, winnerDeletedBoard),
      ]) {
        expect(
          () => TaskBoardSync.merge(
            primary: first,
            secondary: second,
            baseline: null,
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
                  (error) => error.conflictedLabelIds,
                  'conflictedLabelIds',
                  contains(scopedId),
                ),
          ),
          reason: 'Without baseline, live label vs tombstone must require explicit conflict resolution',
        );
        final mergedNoBase = TaskBoardSync.merge(
          primary: first,
          secondary: second,
          baseline: null,
          labelConflictResolutions: const <String, TdfDeletionResolution>{
            scopedId: TdfDeletionResolution.delete,
          },
          evaluationTime: t(30),
        );
        expect(mergedNoBase.findTask(taskNoBaseId)!.isPriority, isFalse);
        expect(mergedNoBase.queueBlock.taskIds, isEmpty);
      }

      // 4. Inline taskRecoveryResolutions on symmetric secondary refresh (primary g+1 vs secondary g):
      const secKeepId = 'secKeep001';
      const secDropId = 'secDrop001';
      const secUnresId = 'secUnrs001';
      final primaryGen2 = TaskBoard.evaluate(
        tasks: const <TaskItem>[],
        deletedBlock: TdfDeletedBlock(generation: 2),
        evaluationTime: t(20),
      );
      final secondaryGen1 = TaskBoard.evaluate(
        tasks: <TaskItem>[
          makeTask(secKeepId, 'Secondary Keep', 12),
          makeTask(secDropId, 'Secondary Drop', 13),
          makeTask(secUnresId, 'Secondary Unresolved', 14),
        ],
        deletedBlock: TdfDeletedBlock(generation: 1),
        queueBlock: makeQueue(14, const <String>[secKeepId, secDropId]),
        evaluationTime: t(20),
      );

      // Partial resolution leaves secUnresId unresolved -> throws RecoveryRequired for secUnresId only!
      expect(
        () => TaskBoardSync.merge(
          primary: primaryGen2,
          secondary: secondaryGen1,
          acknowledgedGeneration: 1,
          taskRecoveryResolutions: const <String, TdfRecoveryResolution>{
            secKeepId: TdfRecoveryResolution.recoverAsNew,
            secDropId: TdfRecoveryResolution.discard,
          },
          evaluationTime: t(30),
        ),
        throwsSyncOutcome(
          TdfSyncOutcomeKind.recoveryRequired,
          ambiguousTasks: equals(<String>[secUnresId]),
        ),
      );

      // Resolving all three succeeds cleanly!
      final inlineResolved = TaskBoardSync.merge(
        primary: primaryGen2,
        secondary: secondaryGen1,
        acknowledgedGeneration: 1,
        taskRecoveryResolutions: const <String, TdfRecoveryResolution>{
          secKeepId: TdfRecoveryResolution.recoverAsNew,
          secDropId: TdfRecoveryResolution.discard,
          secUnresId: TdfRecoveryResolution.discard,
        },
        evaluationTime: t(30),
      );
      expect(inlineResolved.allTasks.length, equals(1));
      expect(inlineResolved.allTasks.single.id, isNot(equals(secKeepId)));
      expect(inlineResolved.allTasks.single.title, equals('Secondary Keep'));
      expect(
        inlineResolved.queueBlock.taskIds,
        equals(<String>[inlineResolved.allTasks.single.id]),
      );
    });

    test('stampAndNormalize and merge enforce TDF-PUB-004 retention pruning and single-increment generation across retries', () {
      final tOldDel = DateTime.utc(2026, 9, 1, 8, 0, 0);
      final tOldDone = DateTime.utc(2026, 9, 15, 8, 0, 0);
      final tRecentDone = DateTime.utc(2026, 11, 10, 8, 0, 0);
      final tNow = DateTime.utc(2026, 11, 15, 12, 0, 0);

      final board = TaskBoard.evaluate(
        tasks: <TaskItem>[
          TaskItem(
            id: 'doneOld001',
            title: 'Completed Over 30d Ago',
            createdAt: DateTime.utc(2026, 9, 1, 8, 0, 0),
            modifiedAt: tOldDone,
            completedAt: tOldDone,
            isCompleted: true,
            completions: 3,
          ),
          TaskItem(
            id: 'doneNew002',
            title: 'Completed Recently With Expired Blocker',
            createdAt: DateTime.utc(2026, 11, 1, 8, 0, 0),
            modifiedAt: tRecentDone,
            completedAt: tRecentDone,
            isCompleted: true,
            completions: 1,
            blockedByTaskIds: const <String>['expDel0001'],
            dependencies: const <TdfTaskDependency>[
              TdfTaskDependency(taskId: 'expDel0001', requiredCompletion: 1),
            ],
          ),
          TaskItem(
            id: 'openDep003',
            title: 'Open Task Blocked On Expired Tombstone',
            createdAt: DateTime.utc(2026, 11, 1, 8, 0, 0),
            modifiedAt: tRecentDone,
            blockedByTaskIds: const <String>['expDel0001'],
            dependencies: const <TdfTaskDependency>[
              TdfTaskDependency(taskId: 'expDel0001', requiredCompletion: 1),
            ],
          ),
        ],
        deletedBlock: TdfDeletedBlock(
          generation: 2,
          tasks: <TdfDeletedTaskRecord>[
            TdfDeletedTaskRecord(taskId: 'expDel0001', deletedAt: tOldDel),
          ],
          labels: <TdfDeletedLabelRecord>[
            TdfDeletedLabelRecord(labelId: 'expLbl0001', deletedAt: tOldDel),
          ],
        ),
        queueBlock: TdfQueueBlock(
          modifiedAt: tRecentDone,
          taskIds: const <String>['openDep003'],
        ),
        evaluationTime: tNow,
        pruneExpiredCompleted: false,
      );

      // Deferred mode must NOT prune >30d Completed or >30d deleted or increment generation:
      final deferredBoard = TaskBoardSync.stampAndNormalize(
        board,
        evaluationTime: tNow,
        cleanupMode: TdfCleanupMode.deferred,
      );
      expect(deferredBoard.findTask('doneOld001'), isNotNull);
      expect(deferredBoard.deletedBlock.generation, equals(2));
      expect(
        deferredBoard.deletedBlock.findTaskRecord('expDel0001'),
        isNotNull,
      );

      // FinalStage stampAndNormalize must GC >30d Completed into deleted AND expire >30d tombstones AND strip blocked on Completed + Open AND increment generation once (2 -> 3):
      final finalBoard = TaskBoardSync.stampAndNormalize(
        board,
        evaluationTime: tNow,
        cleanupMode: TdfCleanupMode.finalStage,
      );
      expect(finalBoard.findTask('doneOld001'), isNull);
      expect(
        finalBoard.deletedBlock.findTaskRecord('doneOld001')?.deletedAt,
        equals(tNow),
      );
      expect(
        finalBoard.deletedBlock
            .findTaskRecord('doneOld001')
            ?.completionsCheckpoint,
        equals(3),
      );
      expect(finalBoard.deletedBlock.findTaskRecord('expDel0001'), isNull);
      expect(finalBoard.deletedBlock.findLabelRecord('expLbl0001'), isNull);
      expect(
        finalBoard.deletedBlock.generation,
        equals(3),
        reason: 'Multiple expired tombstones + Completed GC must increment generation once (2 -> 3)',
      );
      expect(
        finalBoard.findTask('doneNew002')?.dependencies,
        isEmpty,
        reason: 'Completed task blocked reference targeting expired tombstone must also be stripped',
      );
      expect(finalBoard.findTask('openDep003')?.dependencies, isEmpty);

      // Retry guard: if Attempt 0 already incremented primary from 2 -> 3, Step 3 retry merging against secondary at gen 2 with another >30d tombstone keeps generation at 3!
      final secondaryRetry = TaskBoard.evaluate(
        tasks: const <TaskItem>[],
        deletedBlock: TdfDeletedBlock(
          generation: 2,
          locations: <TdfDeletedLocationRecord>[
            TdfDeletedLocationRecord(
              locationId: 'expLoc0001',
              deletedAt: tOldDel,
            ),
          ],
        ),
        evaluationTime: tNow,
      );
      final retried = TaskBoardSync.merge(
        primary: finalBoard,
        secondary: secondaryRetry,
        acknowledgedGeneration: 2,
        preTransactionPrimaryGeneration: 2,
        evaluationTime: tNow,
        cleanupMode: TdfCleanupMode.finalStage,
      );
      expect(
        retried.deletedBlock.generation,
        equals(3),
        reason: 'Step 3 retry within same guarded transaction must not double-increment generation to 4',
      );
      expect(retried.deletedBlock.findLocationRecord('expLoc0001'), isNull);
    });
  });
}
