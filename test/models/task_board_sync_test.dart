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
import 'package:tiertask/models/tdf_sync_metadata.dart';
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
tdf 0.6.0
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
tdf 0.6.0
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
    test('round-trips WorkspaceSyncState TTS v3 binary encoding including deletedLocationTimestamps and localSourceDigest and decodes TTS v2 payloads', () async {
      final state = WorkspaceSyncState(
        lastSyncedLocalTdf: 'tdf 0.6.0\n\ntask 000001OkD2 {\n    name "Local"\n    created 2026-11-01 08:00\n}\n',
        lastSyncedRemoteTdf: 'tdf 0.6.0\n\ntask 000001OkD2 {\n    name "Remote"\n    created 2026-11-01 08:00\n}\n',
        deletedLabelTimestamps: <String, DateTime>{
          'work00OkD2': DateTime.utc(2026, 11, 2, 10, 15, 30),
          'home00OkD2': DateTime.utc(2026, 11, 2, 11, 0, 0),
        },
        deletedLocationTimestamps: <String, DateTime>{
          'loc001OkD2': DateTime.utc(2026, 11, 2, 12, 30, 45),
        },
        acknowledgedLocalGeneration: 4,
        acknowledgedRemoteGeneration: 7,
        localSourceDigest:
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );

      final encodedBytes = state.toBytes();
      expect(encodedBytes[3], equals(3), reason: 'Must encode TTS v3 header');
      final decoded = WorkspaceSyncState.fromBytes(encodedBytes);
      expect(decoded, equals(state));
      expect(decoded.hashCode, equals(state.hashCode));
      expect(decoded.acknowledgedLocalGeneration, equals(4));
      expect(decoded.acknowledgedRemoteGeneration, equals(7));
      expect(
        decoded.deletedLocationTimestamps['loc001OkD2'],
        equals(DateTime.utc(2026, 11, 2, 12, 30, 45)),
      );
      expect(
        decoded.localSourceDigest,
        equals(
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        ),
      );
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
  });
}
