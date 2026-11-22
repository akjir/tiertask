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
import 'package:tiertask/models/task_board.dart';
import 'package:tiertask/models/task_item.dart';
import 'package:tiertask/models/task_tier.dart';
import 'package:tiertask/models/tdf_error.dart';
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/tdf_timezone.dart';

void main() {
  final fixedNow = DateTime.utc(2026, 11, 4, 12);

  group('TDF 0.5.1 Section 5.5 and 6.11.3 Queue-Driven Tier Derivation', () {
    test('preserves saved queue position across blocking and release (A..J table) without rewriting queue order or revisions', () {
      final ids = <String>[
        'taskA00001',
        'taskB00002',
        'taskC00003',
        'taskD00004',
        'taskE00005',
        'taskF00006',
        'taskG00007',
        'taskH00008',
        'taskI00009',
        'taskJ00010',
      ];
      final tasksWithABlocked = <TaskItem>[
        for (var i = 0; i < ids.length; i++)
          TaskItem(
            id: ids[i],
            title: 'Task ${ids[i]}',
            createdAt: DateTime.utc(2026, 11, 1, 8),
            suspendedAt: i == 0 ? DateTime.utc(2026, 11, 5) : null,
          ),
      ];
      final initialQueue = TdfQueueBlock(
        modifiedAt: DateTime.utc(2026, 11, 1, 9),
        taskIds: ids,
      );

      final blockedBoard = TaskBoard.evaluate(
        tasks: tasksWithABlocked,
        evaluationTime: fixedNow,
        queueBlock: initialQueue,
      );
      expect(
        blockedBoard.focus.map((task) => task.id),
        equals(['taskB00002', 'taskC00003', 'taskD00004']),
        reason: 'While A is blocked, B, C, D occupy Focus',
      );
      expect(
        blockedBoard.ready.map((task) => task.id),
        equals([
          'taskE00005',
          'taskF00006',
          'taskG00007',
          'taskH00008',
          'taskI00009',
        ]),
        reason: 'While A is blocked, E, F, G, H, I occupy Ready',
      );
      expect(
        blockedBoard.planned.map((task) => task.id),
        equals(['taskJ00010']),
        reason: 'While A is blocked, J occupies Planned',
      );
      expect(
        blockedBoard.blocked.map((task) => task.id),
        equals(['taskA00001']),
      );
      expect(
        blockedBoard.queueTaskIds,
        equals(ids),
        reason: 'Blocking must preserve saved queue order',
      );

      final releasedBoard = blockedBoard.applyAutoPull(
        currentDate: DateTime.utc(2026, 11, 5, 1),
      );
      expect(
        releasedBoard.focus.map((task) => task.id),
        equals(['taskA00001', 'taskB00002', 'taskC00003']),
        reason: 'When A becomes eligible, it reclaims slot 1 and displaces D to Ready',
      );
      expect(
        releasedBoard.ready.map((task) => task.id),
        equals([
          'taskD00004',
          'taskE00005',
          'taskF00006',
          'taskG00007',
          'taskH00008',
        ]),
        reason: 'D..H occupy Ready after A reclaims slot 1',
      );
      expect(
        releasedBoard.planned.map((task) => task.id),
        equals(['taskI00009', 'taskJ00010']),
        reason: 'I and J occupy Planned after A reclaims slot 1',
      );
      expect(releasedBoard.blocked, isEmpty);
      expect(
        releasedBoard.queueBlock,
        equals(initialQueue),
        reason:
            'Automatic release must not rewrite queue order or queue.modified',
      );
    });

    test('preserves interleaved priority and regular relative queue order regardless of createdAt timestamps', () {
      final tasks = <TaskItem>[
        TaskItem(
          id: 'reg1000001',
          title: 'Regular 1 (later timestamp, earlier in queue)',
          createdAt: DateTime.utc(2026, 11, 4, 11),
        ),
        TaskItem(
          id: 'prio100001',
          title: 'Priority 1 (later timestamp, earlier in queue)',
          isPriority: true,
          createdAt: DateTime.utc(2026, 11, 4, 11, 30),
        ),
        TaskItem(
          id: 'reg2000002',
          title: 'Regular 2 (earlier timestamp, later in queue)',
          createdAt: DateTime.utc(2026, 11, 4, 8),
        ),
        TaskItem(
          id: 'prio200002',
          title: 'Priority 2 (earlier timestamp, later in queue)',
          isPriority: true,
          createdAt: DateTime.utc(2026, 11, 4, 7),
        ),
      ];
      final queue = TdfQueueBlock(
        modifiedAt: fixedNow,
        taskIds: const <String>[
          'reg1000001',
          'prio100001',
          'reg2000002',
          'prio200002',
        ],
      );
      final board = TaskBoard.evaluate(
        tasks: tasks,
        evaluationTime: fixedNow,
        queueBlock: queue,
      );
      expect(
        board.focus.map((task) => task.id),
        equals(['prio100001', 'prio200002', 'reg1000001']),
        reason: 'Section 5.5 groups priority before regular while preserving saved queue order within each group',
      );
      expect(board.ready.map((task) => task.id), equals(['reg2000002']));
    });

    test('derives unqueued task with expired finite suspended lock as Someday without mutating suspended, modified, or queue per Sections 5.3, 5.4, and 6.10.1', () {
      final unqueuedDeferred = TaskItem(
        id: 'unqdefOkD2',
        title: 'Unqueued Deferred Task',
        createdAt: DateTime.utc(2026, 11, 1, 8),
        modifiedAt: DateTime.utc(2026, 11, 1, 8),
        suspendedAt: DateTime.utc(2026, 11, 5),
      );
      final whileSuspended = TaskBoard.evaluate(
        tasks: <TaskItem>[unqueuedDeferred],
        evaluationTime: fixedNow,
        queueBlock: TdfQueueBlock.empty,
      );
      expect(
        whileSuspended.blocked.map((task) => task.id),
        equals(['unqdefOkD2']),
        reason: 'Section 5.4: Unqueued task with active suspended lock must be Blocked',
      );
      expect(whileSuspended.queueTaskIds, isEmpty);

      final afterExpiry = whileSuspended.applyAutoPull(
        currentDate: DateTime.utc(2026, 11, 5, 1),
      );
      expect(
        afterExpiry.someday.map((task) => task.id),
        equals(['unqdefOkD2']),
        reason: 'Section 5.3 and 6.10.1: When finite suspended expires on an unqueued task, derive directly as Someday without queuing',
      );
      expect(afterExpiry.queueTaskIds, isEmpty);
      expect(
        afterExpiry.findTask('unqdefOkD2')!.suspendedAt,
        equals(DateTime.utc(2026, 11, 5)),
        reason: 'Section 6.10.1: Read-only evaluation must not strip expired suspended',
      );
      expect(
        afterExpiry.findTask('unqdefOkD2')!.modifiedAt,
        equals(DateTime.utc(2026, 11, 1, 8)),
        reason:
            'Section 6.10.1: Read-only evaluation must not advance modifiedAt',
      );
    });
  });

  group('TDF 0.5.1 Section 6.5 Restoration Verification Cases', () {
    test('restores task with suspended forever to Someday, future/expired deferral to Planned, Focus with unmet prerequisite to Blocked, and preserves completions + repeat clock while rearming prerequisites', () {
      final openPrereq = TaskItem(
        id: 'prereq0001',
        title: 'Open Prerequisite',
        completions: 4,
        createdAt: fixedNow,
      );
      final finishedForever = TaskItem(
        id: 'forever001',
        title: 'Finished with forever',
        isCompleted: true,
        completedAt: fixedNow,
        completions: 7,
        isPriority: true,
        isSuspendedForever: true,
        dueAt: DateTime.utc(2026, 11, 10, 12),
        origin: const TaskOrigin(namespace: 'github', externalKey: 'issue-99'),
        repeatRule: const TaskRepeatRule(
          count: 2,
          unit: RepeatUnit.days,
          clock: TdfRepeatClock(hour: 9, minute: 30),
        ),
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'prereq0001', requiredCompletion: 3),
        ],
        subtasks: const <SubtaskItem>[
          SubtaskItem(title: 'Step 1', isCompleted: true),
        ],
      );

      final initialBoard = TaskBoard.evaluate(
        tasks: <TaskItem>[openPrereq, finishedForever],
        evaluationTime: fixedNow,
        queueBlock: TdfQueueBlock(
          modifiedAt: fixedNow,
          taskIds: const <String>['prereq0001'],
        ),
      );

      final restoredSomeday = initialBoard.restoreTask(
        'forever001',
        targetTier: TaskTier.someday,
        currentDate: fixedNow.add(const Duration(minutes: 5)),
      );
      final somedayTask = restoredSomeday.findTask('forever001')!;
      expect(
        restoredSomeday.someday.map((task) => task.id),
        equals(['forever001']),
        reason: 'Restoring a task with suspended forever to Someday must clear suspended forever and classify as Someday',
      );
      expect(somedayTask.isCompleted, isFalse);
      expect(somedayTask.completedAt, isNull);
      expect(somedayTask.isSuspendedForever, isFalse);
      expect(somedayTask.suspendedAt, isNull);
      expect(
        somedayTask.dueAt,
        isNull,
        reason: 'Section 6.5: Restoring a task from Completed must clear due',
      );
      expect(
        somedayTask.origin,
        equals(const TaskOrigin(namespace: 'github', externalKey: 'issue-99')),
        reason:
            'Section 6.5: Restoring a task from Completed must preserve origin',
      );
      expect(somedayTask.isPriority, isFalse);
      expect(
        somedayTask.completions,
        equals(7),
        reason: 'Restoration must preserve completion counter 7',
      );
      expect(
        somedayTask.repeatRule?.clock,
        equals(const TdfRepeatClock(hour: 9, minute: 30)),
        reason: 'Restoration must preserve repeat rule clock',
      );
      expect(
        somedayTask.subtasks.single.isCompleted,
        isFalse,
        reason: 'Restoration must reset subtasks to false',
      );
      expect(
        somedayTask.dependencies.single.requiredCompletion,
        equals(5),
        reason:
            'Restoration must rearm open prerequisite at counter (4) + 1 = 5',
      );
      expect(
        restoredSomeday.queueTaskIds.contains('forever001'),
        isFalse,
        reason: 'Restoring to Someday must keep the task outside queue',
      );

      final restoredFocusBlocked = initialBoard.restoreTask(
        'forever001',
        targetTier: TaskTier.focus,
        currentDate: fixedNow.add(const Duration(minutes: 5)),
      );
      final focusRestoredTask = restoredFocusBlocked.findTask('forever001')!;
      expect(
        restoredFocusBlocked.blocked.map((task) => task.id),
        equals(['forever001']),
        reason: 'Restoring to Focus with an unmet rearmed prerequisite (4 < 5) must classify as Blocked',
      );
      expect(focusRestoredTask.isPriority, isTrue);
      expect(focusRestoredTask.isSuspendedForever, isFalse);
      expect(focusRestoredTask.suspendedAt, isNull);
      expect(
        restoredFocusBlocked.queueTaskIds,
        equals(['prereq0001', 'forever001']),
        reason: 'Restoring to Focus must append task ID to queue',
      );
    });
  });

  group('TDF 0.5.1 Section 6.9.7 Prerequisite Completion Counter Verification Cases', () {
    test('evaluates completion thresholds, rearms recurring dependents on completion, guards expectedCompletions, and rejects MAX_COMPLETIONS overflow', () {
      final backupTask = TaskItem(
        id: '8jKaCdOkD2',
        title: 'Create backup',
        createdAt: DateTime.utc(2026, 11, 1, 8),
        modifiedAt: DateTime.utc(2026, 11, 4, 8),
        completions: 7,
        repeatRule: const TaskRepeatRule(
          count: 1,
          unit: RepeatUnit.days,
          clock: TdfRepeatClock(hour: 9),
        ),
      );
      final updateTask = TaskItem(
        id: '3nQp7ROkB8',
        title: 'Install update',
        createdAt: DateTime.utc(2026, 11, 4, 9),
        modifiedAt: DateTime.utc(2026, 11, 4, 9),
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: '8jKaCdOkD2', requiredCompletion: 8),
        ],
        repeatRule: const TaskRepeatRule(count: 1, unit: RepeatUnit.days),
      );

      var board = TaskBoard.evaluate(
        tasks: <TaskItem>[backupTask, updateTask],
        evaluationTime: fixedNow,
        queueBlock: TdfQueueBlock(
          modifiedAt: DateTime.utc(2026, 11, 4, 9),
          taskIds: const <String>['8jKaCdOkD2', '3nQp7ROkB8'],
        ),
      );

      expect(board.focus.map((task) => task.id), equals(['8jKaCdOkD2']));
      expect(
        board.blocked.map((task) => task.id),
        equals(['3nQp7ROkB8']),
        reason: 'Prerequisite counter is 7, requirement is 8 -> dependent is blocked',
      );

      // Retry with mismatched expectedCompletions must be a no-op
      final ignoredRetry = board.completeTask(
        '8jKaCdOkD2',
        currentDate: fixedNow,
        timeZone: TdfTimeZoneContext.utc,
        expectedCompletions: 6,
      );
      expect(
        ignoredRetry.findTask('8jKaCdOkD2')?.completions,
        equals(7),
        reason: 'Mismatched expectedCompletions must leave task unchanged',
      );

      // Complete backup (7 -> 8)
      board = board.completeTask(
        '8jKaCdOkD2',
        currentDate: fixedNow,
        timeZone: TdfTimeZoneContext.utc,
        expectedCompletions: 7,
      );
      expect(board.findTask('8jKaCdOkD2')?.completions, equals(8));
      expect(
        board.focus.map((task) => task.id),
        equals(['3nQp7ROkB8']),
        reason: 'Prerequisite advancing to 8 releases updateTask into Focus while backupTask is deferred',
      );

      // Advance backup again (8 -> 9) while deferred
      board = board.completeTask(
        '8jKaCdOkD2',
        currentDate: fixedNow.add(const Duration(minutes: 10)),
        timeZone: TdfTimeZoneContext.utc,
        expectedCompletions: 8,
      );
      expect(board.findTask('8jKaCdOkD2')?.completions, equals(9));
      expect(
        board.focus.map((task) => task.id),
        equals(['3nQp7ROkB8']),
        reason: 'Prerequisite advancing to 9 keeps requirement 8 satisfied',
      );

      // Complete recurring dependent updateTask while backupTask is open at 9 -> rearms requirement to 10
      board = board.completeTask(
        '3nQp7ROkB8',
        currentDate: fixedNow.add(const Duration(minutes: 20)),
        timeZone: TdfTimeZoneContext.utc,
      );
      expect(
        board.findTask('3nQp7ROkB8')?.dependencies.single.requiredCompletion,
        equals(10),
        reason: 'Completing recurring dependent while open prerequisite is at 9 must capture requirement 10',
      );

      // Complete backupTask (9 -> 10) during updateTask's deferral
      board = board.completeTask(
        '8jKaCdOkD2',
        currentDate: fixedNow.add(const Duration(minutes: 30)),
        timeZone: TdfTimeZoneContext.utc,
      );
      expect(board.findTask('8jKaCdOkD2')?.completions, equals(10));

      // Wake both tasks on 2026-11-05 10:00 UTC -> updateTask's requirement 10 is already satisfied!
      final wokenBoard = board.applyAutoPull(
        currentDate: DateTime.utc(2026, 11, 5, 10),
      );
      expect(
        wokenBoard.focus.map((task) => task.id),
        equals(['8jKaCdOkD2', '3nQp7ROkB8']),
        reason: 'Requirement 10 satisfied during deferral must allow dependent to wake into Focus',
      );

      // Overflow bound check
      final maxCounterTask = TaskItem(
        id: 'max000OkD2',
        title: 'At Max Counter',
        completions: TdfTaskDependency.maxCompletions,
        createdAt: fixedNow,
      );
      final maxBoard = TaskBoard.evaluate(
        tasks: <TaskItem>[maxCounterTask],
        evaluationTime: fixedNow,
        queueBlock: TdfQueueBlock(
          modifiedAt: fixedNow,
          taskIds: const <String>['max000OkD2'],
        ),
      );
      expect(
        () => maxBoard.completeTask('max000OkD2', currentDate: fixedNow),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason: 'Exceeding MAX_COMPLETIONS must fail with LimitExceeded without partial changes',
      );
    });
  });

  group('TDF 0.5.1 Section 6.8 Deletion Records and 30-Day Cleanup', () {
    test('records task and label deletions, records pruned completed tasks at deletion time, and increments generation once during 30-day cleanup', () {
      final label = TdfLabel(
        id: 'lbl000OkD2',
        name: 'Work',
        modifiedAt: DateTime.utc(2026, 11, 1, 8),
      );
      final activeTask = TaskItem(
        id: 'act000OkD2',
        title: 'Active Task',
        completions: 3,
        createdAt: DateTime.utc(2026, 11, 1, 8),
        modifiedAt: DateTime.utc(2026, 11, 1, 8),
        labelIds: const <String>['lbl000OkD2'],
      );
      final expiredCompleted = TaskItem(
        id: 'exp000OkD2',
        title: 'Completed 31 Days Ago',
        isCompleted: true,
        completions: 2,
        createdAt: DateTime.utc(2026, 9, 1, 8),
        completedAt: DateTime.utc(2026, 10, 1, 8),
        modifiedAt: DateTime.utc(2026, 10, 1, 8),
      );

      var board = TaskBoard.evaluate(
        tasks: <TaskItem>[activeTask, expiredCompleted],
        labels: <TdfLabel>[label],
        evaluationTime: fixedNow,
        queueBlock: TdfQueueBlock(
          modifiedAt: DateTime.utc(2026, 11, 1, 8),
          taskIds: const <String>['act000OkD2'],
        ),
      );

      board = board.deleteLabel('lbl000OkD2', currentDate: fixedNow);
      expect(board.labels, isEmpty);
      expect(board.findTask('act000OkD2')?.labelIds, isEmpty);
      expect(board.findTask('act000OkD2')?.modifiedAt, equals(fixedNow));
      expect(
        board.deletedBlock.findLabelRecord('lbl000OkD2'),
        equals(
          TdfDeletedLabelRecord(labelId: 'lbl000OkD2', deletedAt: fixedNow),
        ),
      );
      expect(
        board.deletedBlock.generation,
        equals(0),
        reason: 'Creating a deletion record must not increment generation',
      );

      final deleteTime = fixedNow.add(const Duration(minutes: 5));
      board = board.deleteTask('act000OkD2', currentDate: deleteTime);
      expect(board.findTask('act000OkD2'), isNull);
      expect(board.queueTaskIds, isEmpty);
      expect(
        board.deletedBlock.findTaskRecord('act000OkD2'),
        equals(
          TdfDeletedTaskRecord(
            taskId: 'act000OkD2',
            deletedAt: deleteTime,
            completionsCheckpoint: 3,
          ),
        ),
      );

      // Pruning expiredCompleted must record its deletion at prune time, not its old finished time
      board = board.pruneCompletedTasks(currentDate: deleteTime);
      expect(board.completed, isEmpty);
      expect(
        board.deletedBlock.findTaskRecord('exp000OkD2'),
        equals(
          TdfDeletedTaskRecord(
            taskId: 'exp000OkD2',
            deletedAt: deleteTime,
            completionsCheckpoint: 2,
          ),
        ),
        reason: 'Section 6.8.1: Pruning a completed task after 30 days must create a deletion record with the current deletion revision and completion counter',
      );

      // At exactly 2,592,000 seconds after fixedNow, lbl000OkD2 is still kept
      final exact30Days = fixedNow.add(const Duration(seconds: 2592000));
      final unchangedCleanup = board.cleanupExpiredDeletions(
        currentDate: exact30Days,
      );
      expect(unchangedCleanup.deletedBlock.generation, equals(0));
      expect(unchangedCleanup.deletedBlock.totalRecords, equals(3));

      // At 2,592,001 seconds after deleteTime, all 3 records expire and generation increments once to 1
      final after30DaysAll = deleteTime.add(const Duration(seconds: 2592001));
      final cleanedBoard = board.cleanupExpiredDeletions(
        currentDate: after30DaysAll,
      );
      expect(cleanedBoard.deletedBlock.tasks, isEmpty);
      expect(cleanedBoard.deletedBlock.labels, isEmpty);
      expect(
        cleanedBoard.deletedBlock.generation,
        equals(1),
        reason: 'Section 6.8.3: Removing multiple expired records in one cleanup increments generation once and preserves nonzero generation when empty',
      );

      final boardWithExpiredTaskPrereq = TaskBoard.evaluate(
        tasks: <TaskItem>[
          TaskItem(
            id: 'liveDepTask',
            title: 'Live Task Depending on Expired Tombstone and Forward Ref',
            createdAt: fixedNow,
            modifiedAt: fixedNow,
            dependencies: const <TdfTaskDependency>[
              TdfTaskDependency(taskId: 'oldDelTask'),
              TdfTaskDependency(taskId: 'fwdRefTask'),
            ],
          ),
        ],
        evaluationTime: after30DaysAll,
        queueBlock: TdfQueueBlock(
          modifiedAt: fixedNow,
          taskIds: const <String>['liveDepTask'],
        ),
        deletedBlock: TdfDeletedBlock(
          generation: 2,
          tasks: <TdfDeletedTaskRecord>[
            TdfDeletedTaskRecord(
              taskId: 'oldDelTask',
              deletedAt: fixedNow,
              completionsCheckpoint: 1,
            ),
          ],
          locations: <TdfDeletedLocationRecord>[
            TdfDeletedLocationRecord(
              locationId: 'oldDelLoc1',
              deletedAt: fixedNow,
            ),
          ],
        ),
      );
      final afterPrereqHygiene = boardWithExpiredTaskPrereq
          .cleanupExpiredDeletions(currentDate: after30DaysAll);
      expect(afterPrereqHygiene.deletedBlock.tasks, isEmpty);
      expect(afterPrereqHygiene.deletedBlock.locations, isEmpty);
      expect(afterPrereqHygiene.deletedBlock.generation, equals(3));
      expect(
        afterPrereqHygiene.findTask('liveDepTask')!.dependencies,
        equals(const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'fwdRefTask'),
        ]),
        reason: 'Section 6.8.3: Expiring a task tombstone after 30 days must strip blocked references to that expired ID while preserving forward references',
      );
      expect(
        afterPrereqHygiene.findTask('liveDepTask')!.modifiedAt,
        equals(after30DaysAll),
        reason: 'Section 6.8.3: Stripping an expired prerequisite reference must advance task.modified',
      );
    });

    test('preserves recurring-to-recurring blocked pipelines across prerequisite completion and rearms dependent on completion', () {
      final recPrereq = TaskItem(
        id: 'recPrereq1',
        title: 'Daily Build',
        createdAt: fixedNow,
        modifiedAt: fixedNow,
        repeatRule: const TaskRepeatRule(count: 1, unit: RepeatUnit.days),
      );
      final recDependent = TaskItem(
        id: 'recDep0001',
        title: 'Daily Smoke Test',
        createdAt: fixedNow,
        modifiedAt: fixedNow,
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'recPrereq1'),
        ],
        repeatRule: const TaskRepeatRule(count: 1, unit: RepeatUnit.days),
      );
      final oneOffDependent = TaskItem(
        id: 'oneDep0001',
        title: 'One-Off Verification',
        createdAt: fixedNow,
        modifiedAt: fixedNow,
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'recPrereq1'),
        ],
      );

      var board = TaskBoard.evaluate(
        tasks: <TaskItem>[recPrereq, recDependent, oneOffDependent],
        evaluationTime: fixedNow,
        timeZone: TdfTimeZoneContext.utc,
        queueBlock: TdfQueueBlock(
          modifiedAt: fixedNow,
          taskIds: const <String>['recPrereq1', 'recDep0001', 'oneDep0001'],
        ),
      );

      // Complete recurring prerequisite -> completions becomes 1:
      final t1 = fixedNow.add(const Duration(minutes: 10));
      board = board.completeTask(
        'recPrereq1',
        currentDate: t1,
        timeZone: TdfTimeZoneContext.utc,
      );
      expect(
        board.findTask('oneDep0001')!.dependencies,
        isEmpty,
        reason: 'Non-recurring dependent on recurring prerequisite has its satisfied blocked directive cleaned immediately',
      );
      expect(
        board.findTask('recDep0001')!.dependencies,
        equals(const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'recPrereq1'),
        ]),
        reason: 'Recurring-to-recurring pipeline must preserve blocked directive so dependent can rearm on completion',
      );
      expect(board.focus.map((t) => t.id), contains('recDep0001'));

      // Complete recurring dependent -> rearms requiredCompletion to prereq.completions + 1 == 2!
      final t2 = fixedNow.add(const Duration(minutes: 20));
      board = board.completeTask(
        'recDep0001',
        currentDate: t2,
        timeZone: TdfTimeZoneContext.utc,
      );
      expect(
        board.findTask('recDep0001')!.dependencies,
        equals(const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'recPrereq1', requiredCompletion: 2),
        ]),
      );
    });

    test('TDF 0.8.0 TDF-PUB-004 strips expired task blocked refs on Completed tasks, prunes scopedHidden Completed tasks, and rejects maxTdfSyncGeneration overflow', () {
      final tDel = DateTime.utc(2026, 10, 1, 12);
      final exact30d = tDel.add(const Duration(seconds: 2592000));
      final over30d = tDel.add(const Duration(seconds: 2592001));
      final scopedLabel = TdfLabel(
        id: 'scpLbl0001',
        name: 'Scoped',
        isScoped: true,
        modifiedAt: tDel,
      );

      // 1. Completed task (both global and scoped-hidden) carrying blocked <expired-id> has it stripped on 30-day tombstone expiry:
      final doneWithStaleBlocked = TaskItem(
        id: 'doneBlk001',
        title: 'Completed Task Retaining Tombstoned Blocker',
        isCompleted: true,
        completedAt: tDel.add(const Duration(days: 10)),
        completions: 1,
        createdAt: tDel,
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'expTomb001', requiredCompletion: 2),
          TdfTaskDependency(taskId: 'fwdKeep001'),
        ],
      );
      final scopedDoneExpired = TaskItem(
        id: 'scpDoneExp',
        title: 'Scoped Completed Over 30 Days',
        isCompleted: true,
        completedAt: tDel,
        completions: 3,
        createdAt: tDel,
        modifiedAt: tDel,
        labelIds: const <String>['scpLbl0001'],
      );
      final scopedDoneRetainedWithStaleBlocked = TaskItem(
        id: 'scpDoneBlk',
        title: 'Scoped Completed Within 30 Days With Tombstoned Blocker',
        isCompleted: true,
        completedAt: tDel.add(const Duration(days: 5)),
        completions: 1,
        createdAt: tDel,
        labelIds: const <String>['scpLbl0001'],
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'expTomb001'),
        ],
      );

      final initial = TaskBoard.evaluate(
        tasks: <TaskItem>[
          doneWithStaleBlocked,
          scopedDoneExpired,
          scopedDoneRetainedWithStaleBlocked,
        ],
        labels: <TdfLabel>[scopedLabel],
        deletedBlock: TdfDeletedBlock(
          generation: 5,
          tasks: <TdfDeletedTaskRecord>[
            TdfDeletedTaskRecord(
              taskId: 'expTomb001',
              deletedAt: tDel,
              completionsCheckpoint: 2,
            ),
          ],
        ),
        evaluationTime: exact30d,
      );

      // Exact 30 days (2,592,000s) retains both scoped completed task and tombstone:
      expect(
        initial
            .pruneCompletedTasks(currentDate: exact30d)
            .findTask('scpDoneExp'),
        isNotNull,
        reason: 'Exact 2,592,000s Completed task must be retained',
      );
      expect(
        initial
            .cleanupExpiredDeletions(currentDate: exact30d)
            .deletedBlock
            .generation,
        equals(5),
        reason: 'Exact 2,592,000s tombstone must be retained without generation increment',
      );

      // At 2,592,001s: pruneCompletedTasks retires scopedDoneExp into deleted without incrementing generation:
      final afterCompletedGc = initial.pruneCompletedTasks(
        currentDate: over30d,
      );
      expect(
        afterCompletedGc.findTask('scpDoneExp'),
        isNull,
        reason:
            'TDF-PUB-004: scoped Completed task > 2,592,000s must be pruned',
      );
      expect(
        afterCompletedGc.deletedBlock.findTaskRecord('scpDoneExp'),
        equals(
          TdfDeletedTaskRecord(
            taskId: 'scpDoneExp',
            deletedAt: over30d,
            completionsCheckpoint: 3,
          ),
        ),
      );
      expect(afterCompletedGc.deletedBlock.generation, equals(5));

      // cleanupExpiredDeletions retires expTomb001 (while keeping newly pruned scpDoneExp!), increments generation once to 6, and strips expTomb001 on Completed tasks:
      final afterTombstoneGc = afterCompletedGc.cleanupExpiredDeletions(
        currentDate: over30d,
      );
      expect(afterTombstoneGc.deletedBlock.generation, equals(6));
      expect(
        afterTombstoneGc.deletedBlock.findTaskRecord('expTomb001'),
        isNull,
      );
      expect(
        afterTombstoneGc.deletedBlock.findTaskRecord('scpDoneExp'),
        isNotNull,
      );
      final cleanedDone = afterTombstoneGc.findTask('doneBlk001')!;
      expect(
        cleanedDone.dependencies,
        equals(const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'fwdKeep001'),
        ]),
        reason: 'TDF-PUB-004: expiring task tombstone must strip blocked reference even on Completed tasks while preserving forward refs',
      );
      expect(
        cleanedDone.blockedByTaskIds,
        equals(const <String>['fwdKeep001']),
      );
      expect(cleanedDone.modifiedAt, equals(over30d));

      final cleanedScopedDone = afterTombstoneGc.findTask('scpDoneBlk')!;
      expect(cleanedScopedDone.dependencies, isEmpty);
      expect(cleanedScopedDone.modifiedAt, equals(over30d));

      // 2. maxTdfSyncGeneration overflow throws TdfException(limitExceeded) instead of wrapping or FormatException:
      final maxGenBoard = TaskBoard.evaluate(
        tasks: const <TaskItem>[],
        deletedBlock: TdfDeletedBlock(
          generation: maxTdfSyncGeneration,
          tasks: <TdfDeletedTaskRecord>[
            TdfDeletedTaskRecord(taskId: 'expMaxGen1', deletedAt: tDel),
          ],
        ),
        evaluationTime: exact30d,
      );
      expect(
        () => maxGenBoard.cleanupExpiredDeletions(currentDate: over30d),
        throwsA(
          isA<TdfException>().having(
            (error) => error.kind,
            'kind',
            TdfErrorKind.limitExceeded,
          ),
        ),
        reason: 'TDF-PUB-004: generation >= maxTdfSyncGeneration must fail with LimitExceeded instead of wrapping',
      );
    });

    test('editing a Completed recurring task with subtasksAutoFinish via updateTask keeps it Completed', () {
      final t0 = DateTime.utc(2026, 8, 1, 9);
      final t1 = t0.add(const Duration(minutes: 5));
      final t2 = t1.add(const Duration(minutes: 5));
      final completedRecurring = TaskItem(
        id: 'doneRecAf1',
        title: 'Completed Recurring AutoFinish',
        isCompleted: true,
        completions: 4,
        createdAt: t0,
        completedAt: t0,
        modifiedAt: t0,
        repeatRule: const TaskRepeatRule(count: 1, unit: RepeatUnit.days),
        subtasksAutoFinish: true,
        subtasks: const <SubtaskItem>[
          SubtaskItem(title: 'Step A', isCompleted: true),
        ],
      );
      final board = TaskBoard.evaluate(
        tasks: <TaskItem>[completedRecurring],
        evaluationTime: t0,
      );

      // No-op updateTask returns identical board without resurrecting:
      final noOp = board.updateTask(
        'doneRecAf1',
        title: 'Completed Recurring AutoFinish',
        currentDate: t1,
      );
      expect(identical(noOp, board), isTrue);

      // Editing note and adding a new subtask keeps Completed, locks all steps true, preserves completions, and stays out of queue:
      final edited = board.updateTask(
        'doneRecAf1',
        note: 'Updated retrospective note',
        subtasks: const <SubtaskItem>[
          SubtaskItem(title: 'Step A', isCompleted: true),
          SubtaskItem(title: 'Step B'),
        ],
        currentDate: t2,
      );
      final after = edited.findTask('doneRecAf1')!;
      expect(
        after.isCompleted,
        isTrue,
        reason: 'Editing a Completed recurring task with auto-finish must not resurrect it',
      );
      expect(after.completedAt, equals(t0));
      expect(after.completions, equals(4));
      expect(after.note, equals('Updated retrospective note'));
      expect(
        after.subtasks.every((step) => step.isCompleted),
        isTrue,
        reason: 'Subtasks on a Completed task must stay locked true',
      );
      expect(edited.queueTaskIds, isNot(contains('doneRecAf1')));
    });

    test('nextModifiedTimestamp, computeNextMode2Schedule, and nextDueUtc map out-of-bounds timestamps to TdfException(invalidTimestamp)', () {
      final maxUtc = DateTime.utc(9999, 12, 31, 23, 59, 59);
      final minUtc = DateTime.utc(1);
      final tdfInvalidTimestamp = isA<TdfException>().having(
        (error) => error.kind,
        'kind',
        TdfErrorKind.invalidTimestamp,
      );

      // 1. TaskItem.nextModifiedTimestamp overflow & invalid now:
      expect(
        () => TaskItem.nextModifiedTimestamp(maxUtc, maxUtc),
        throwsA(tdfInvalidTimestamp),
        reason: 'nextModifiedTimestamp +1s past 9999 must throw TdfException(invalidTimestamp)',
      );
      expect(
        () => TaskItem.nextModifiedTimestamp(DateTime.utc(10000), null),
        throwsA(tdfInvalidTimestamp),
      );

      // 2. TaskRepeatRule.computeNextMode2Schedule local anchor underflow/overflow when oldAnchor is null:
      const daily = TaskRepeatRule(count: 1, unit: RepeatUnit.days);
      expect(
        () => daily.computeNextMode2Schedule(
          completedAtUtc: DateTime.utc(2026),
          oldDueUtc: minUtc,
          timeZone: TdfTimeZoneContext.fixedOffset(const Duration(hours: -5)),
        ),
        throwsA(tdfInvalidTimestamp),
        reason: '0001-01-01T00:00:00Z in UTC-5 local anchor underflow must throw TdfException(invalidTimestamp)',
      );
      expect(
        () => daily.computeNextMode2Schedule(
          completedAtUtc: maxUtc,
          oldDueUtc: maxUtc,
          timeZone: TdfTimeZoneContext.fixedOffset(const Duration(hours: 2)),
        ),
        throwsA(tdfInvalidTimestamp),
        reason: '9999-12-31T23:59:59Z in UTC+2 local anchor overflow must throw TdfException(invalidTimestamp)',
      );

      // 3. TaskRepeatRule.nextDueUtc 9999 overflow and non-advancing resolved timestamp:
      expect(
        () => daily.nextDueUtc(
          completedAtUtc: maxUtc,
          timeZone: TdfTimeZoneContext.utc,
        ),
        throwsA(tdfInvalidTimestamp),
        reason: 'nextDueUtc past 9999-12-31 must throw TdfException(invalidTimestamp)',
      );
      expect(
        () => daily.nextDueUtc(
          completedAtUtc: DateTime.utc(10000),
          timeZone: TdfTimeZoneContext.utc,
        ),
        throwsA(tdfInvalidTimestamp),
      );
    });
  });
}
