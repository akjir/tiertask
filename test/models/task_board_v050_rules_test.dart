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
import 'package:tiertask/models/tdf_metadata.dart';
import 'package:tiertask/models/tdf_sync_metadata.dart';
import 'package:tiertask/models/tdf_timezone.dart';

void main() {
  final fixedNow = DateTime.utc(2026, 11, 4, 12, 0, 0);

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
            createdAt: DateTime.utc(2026, 11, 1, 8, 0),
            suspendedAt: i == 0 ? DateTime.utc(2026, 11, 5, 0, 0) : null,
          ),
      ];
      final initialQueue = TdfQueueBlock(
        modifiedAt: DateTime.utc(2026, 11, 1, 9, 0, 0),
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
        currentDate: DateTime.utc(2026, 11, 5, 1, 0, 0),
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
          createdAt: DateTime.utc(2026, 11, 4, 11, 0),
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
          createdAt: DateTime.utc(2026, 11, 4, 8, 0),
        ),
        TaskItem(
          id: 'prio200002',
          title: 'Priority 2 (earlier timestamp, later in queue)',
          isPriority: true,
          createdAt: DateTime.utc(2026, 11, 4, 7, 0),
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
        createdAt: DateTime.utc(2026, 11, 1, 8, 0),
        modifiedAt: DateTime.utc(2026, 11, 1, 8, 0),
        suspendedAt: DateTime.utc(2026, 11, 5, 0, 0),
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
        currentDate: DateTime.utc(2026, 11, 5, 1, 0),
      );
      expect(
        afterExpiry.someday.map((task) => task.id),
        equals(['unqdefOkD2']),
        reason: 'Section 5.3 and 6.10.1: When finite suspended expires on an unqueued task, derive directly as Someday without queuing',
      );
      expect(afterExpiry.queueTaskIds, isEmpty);
      expect(
        afterExpiry.findTask('unqdefOkD2')!.suspendedAt,
        equals(DateTime.utc(2026, 11, 5, 0, 0)),
        reason: 'Section 6.10.1: Read-only evaluation must not strip expired suspended',
      );
      expect(
        afterExpiry.findTask('unqdefOkD2')!.modifiedAt,
        equals(DateTime.utc(2026, 11, 1, 8, 0)),
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
        createdAt: DateTime.utc(2026, 11, 1, 8, 0),
        modifiedAt: DateTime.utc(2026, 11, 4, 8, 0),
        completions: 7,
        repeatRule: const TaskRepeatRule(
          count: 1,
          unit: RepeatUnit.days,
          clock: TdfRepeatClock(hour: 9, minute: 0),
        ),
      );
      final updateTask = TaskItem(
        id: '3nQp7ROkB8',
        title: 'Install update',
        createdAt: DateTime.utc(2026, 11, 4, 9, 0),
        modifiedAt: DateTime.utc(2026, 11, 4, 9, 0),
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: '8jKaCdOkD2', requiredCompletion: 8),
        ],
        repeatRule: const TaskRepeatRule(count: 1, unit: RepeatUnit.days),
      );

      var board = TaskBoard.evaluate(
        tasks: <TaskItem>[backupTask, updateTask],
        evaluationTime: fixedNow,
        queueBlock: TdfQueueBlock(
          modifiedAt: DateTime.utc(2026, 11, 4, 9, 0),
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
        currentDate: DateTime.utc(2026, 11, 5, 10, 0, 0),
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
        throwsA(isA<FormatException>()),
        reason: 'Exceeding MAX_COMPLETIONS must fail without partial changes',
      );
    });
  });

  group('TDF 0.5.1 Section 6.8 Deletion Records and 30-Day Cleanup', () {
    test('records task and label deletions, records pruned completed tasks at deletion time, and increments generation once during 30-day cleanup', () {
      final label = TdfLabel(
        id: 'lbl000OkD2',
        name: 'Work',
        modifiedAt: DateTime.utc(2026, 11, 1, 8, 0),
      );
      final activeTask = TaskItem(
        id: 'act000OkD2',
        title: 'Active Task',
        completions: 3,
        createdAt: DateTime.utc(2026, 11, 1, 8, 0),
        modifiedAt: DateTime.utc(2026, 11, 1, 8, 0),
        labelIds: const <String>['lbl000OkD2'],
      );
      final expiredCompleted = TaskItem(
        id: 'exp000OkD2',
        title: 'Completed 31 Days Ago',
        isCompleted: true,
        completions: 2,
        createdAt: DateTime.utc(2026, 9, 1, 8, 0),
        completedAt: DateTime.utc(2026, 10, 1, 8, 0),
        modifiedAt: DateTime.utc(2026, 10, 1, 8, 0),
      );

      var board = TaskBoard.evaluate(
        tasks: <TaskItem>[activeTask, expiredCompleted],
        labels: <TdfLabel>[label],
        evaluationTime: fixedNow,
        queueBlock: TdfQueueBlock(
          modifiedAt: DateTime.utc(2026, 11, 1, 8, 0),
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
    });
  });
}
