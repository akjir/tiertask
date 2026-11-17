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
import 'package:tiertask/services/tdf_service.dart';

void main() {
  const tdfService = TdfService();
  final fixedDate = DateTime.utc(2026, 11, 1, 12, 0);

  group('TDF Section 6 State Transitions, Subtasks Auto-Finish & Retention GC', () {
    test(
      'fills Focus (limit 3) from Ready and Ready (limit 5) from Planned',
      () {
        final board = TaskBoard(
          focus: [TaskItem(id: 'f1', title: 'F1')],
          ready: [
            TaskItem(id: 'b1', title: 'B1'),
            TaskItem(id: 'b2', title: 'B2'),
            TaskItem(id: 'b3', title: 'B3'),
          ],
          planned: [
            TaskItem(id: 'g1', title: 'G1'),
            TaskItem(id: 'g2', title: 'G2'),
            TaskItem(id: 'g3', title: 'G3'),
            TaskItem(id: 'g4', title: 'G4'),
            TaskItem(id: 'g5', title: 'G5'),
          ],
          blocked: [TaskItem(id: 'bl1', title: 'BL1')],
          someday: [TaskItem(id: 'i1', title: 'I1')],
        );

        final cascaded = board.applyAutoPull();

        expect(
          cascaded.focus.map((task) => task.title),
          equals(['F1', 'B1', 'B2']),
        );
        expect(
          cascaded.ready.map((task) => task.title),
          equals(['B3', 'G1', 'G2', 'G3', 'G4']),
        );
        expect(cascaded.planned.map((task) => task.title), equals(['G5']));
        expect(cascaded.blocked.map((task) => task.title), equals(['BL1']));
        expect(cascaded.someday.map((task) => task.title), equals(['I1']));
      },
    );

    test('Quick-Add to Planned cascades to Focus when board has capacity, and Priority sorts ahead of regular tasks', () {
      var board = TaskBoard.empty();
      board = board.addTask(
        'Task 1',
        targetTier: TaskTier.planned,
        currentDate: DateTime.utc(2026, 11, 1, 8, 0),
        id: '000001OkD2',
      );
      board = board.addTask(
        'Task 2',
        targetTier: TaskTier.planned,
        currentDate: DateTime.utc(2026, 11, 1, 8, 5),
        id: '000002OkD2',
      );
      board = board.addTask(
        'Task 3',
        targetTier: TaskTier.planned,
        currentDate: DateTime.utc(2026, 11, 1, 8, 10),
        id: '000003OkD2',
      );

      expect(
        board.focus.map((task) => task.id),
        equals(['000001OkD2', '000002OkD2', '000003OkD2']),
      );

      final updated = board.addTask(
        'Urgent Hotfix',
        targetTier: TaskTier.focus,
        isPriority: true,
        subtasksAutoFinish: true,
        subtasks: const [
          SubtaskItem(title: 'Patch vulnerability'),
          SubtaskItem(title: 'Verify regression tests', isCompleted: true),
        ],
        currentDate: DateTime.utc(2026, 11, 1, 8, 15),
        id: '000004OkD2',
      );

      expect(
        updated.focus.map((task) => task.id),
        equals(['000004OkD2', '000001OkD2', '000002OkD2']),
        reason: 'Priority task must sort to the top of Focus and push 3rd task to Ready',
      );
      expect(updated.ready.map((task) => task.id), equals(['000003OkD2']));

      final serialized = tdfService.serialize(updated);
      expect(serialized, contains('task 000004OkD2 priority {'));
      expect(serialized, contains('subtasks auto-finish {'));
      expect(serialized, contains('step false "Patch vulnerability"'));
      expect(serialized, contains('step true  "Verify regression tests"'));

      final reparsed = tdfService.parse(serialized, evaluationTime: fixedDate);
      expect(
        reparsed.focus.first.subtasks.map((subtask) => subtask.title),
        equals(['Patch vulnerability', 'Verify regression tests']),
      );
    });

    test('completes enclosing task automatically when subtasks has auto-finish and all steps become true', () {
      const autoFinishTdf = '''
tdf 0.8.0

queue {
    modified 2026-11-01 09:05:00
    task auto00OkD2
    task manualOkD2
}

task auto00OkD2 {
    name "Auto-finish task"
    created 2026-11-01 09:00
    subtasks auto-finish {
        step true "Step 1"
        step false "Step 2"
    }
}
task manualOkD2 {
    name "Manual finish task"
    created 2026-11-01 09:05
    subtasks {
        step true "Step A"
        step false "Step B"
    }
}
''';

      var board = tdfService.parse(autoFinishTdf, evaluationTime: fixedDate);
      expect(
        board.focus.map((task) => task.id),
        equals(['auto00OkD2', 'manualOkD2']),
      );

      board = board.toggleSubtask('auto00OkD2', 1, currentDate: fixedDate);
      expect(
        board.completed.map((task) => task.id),
        equals(['auto00OkD2']),
        reason: 'Completing all steps in subtasks auto-finish must transition task to Completed',
      );
      expect(board.focus.map((task) => task.id), equals(['manualOkD2']));

      board = board.toggleSubtask('manualOkD2', 1, currentDate: fixedDate);
      expect(
        board.focus.map((task) => task.id),
        equals(['manualOkD2']),
        reason: 'Completing all steps without auto-finish must keep task open',
      );
    });

    test('completes active task, unblocks dependent tasks, prunes >30d completed tasks (29, 30, 31 day bounds), schedules Someday tasks (Section 6.2), and restores tasks (Section 6.5)', () {
      final board = TaskBoard(
        focus: [
          TaskItem(
            id: 'f1',
            title: 'Finish spec',
            subtasks: const [
              SubtaskItem(title: 'Draft section 1', isCompleted: true),
              SubtaskItem(title: 'Draft section 2', isCompleted: false),
            ],
          ),
          TaskItem(id: 'f2', title: 'Task 2'),
          TaskItem(id: 'f3', title: 'Task 3'),
        ],
        ready: [TaskItem(id: 'b1', title: 'Ready 1')],
        blocked: [
          TaskItem(
            id: 'dep1',
            title: 'Waiting on f1',
            createdAt: DateTime.utc(2026, 11, 1, 9, 0),
            blockedByTaskIds: const ['f1'],
          ),
        ],
        someday: [TaskItem(id: 's1', title: 'Someday Idea')],
        completed: [
          TaskItem(
            id: 'e_keep_29',
            title: '29 Days Ago',
            isCompleted: true,
            completedAt: DateTime.utc(2026, 10, 3, 12, 0),
          ),
          TaskItem(
            id: 'e_keep_30',
            title: '30 Days Ago',
            isCompleted: true,
            completedAt: DateTime.utc(2026, 10, 2, 12, 0),
          ),
          TaskItem(
            id: 'e_prune_31',
            title: '31 Days Ago',
            isCompleted: true,
            completedAt: DateTime.utc(2026, 10, 1, 12, 0),
          ),
        ],
      );

      final afterComplete = board.completeTask('f1', currentDate: fixedDate);

      expect(
        afterComplete.focus.map((task) => task.title),
        equals(['Task 2', 'Task 3', 'Ready 1']),
      );
      expect(
        afterComplete.ready.map((task) => task.id),
        equals(['dep1']),
        reason: 'Completing prerequisite f1 must automatically unblock dep1 into the active cycle',
      );
      expect(afterComplete.blocked, isEmpty);
      expect(
        afterComplete.completed.map((task) => task.title),
        equals(['Finish spec', '29 Days Ago', '30 Days Ago']),
        reason:
            '29 and 30 day old tasks must be kept while 31 day old is pruned',
      );
      expect(
        afterComplete
            .findTask('f1')!
            .subtasks
            .every((step) => step.isCompleted),
        isTrue,
        reason: 'Completing a task with subtasks must mark all subtasks as completed',
      );

      final toggleOnCompleted = afterComplete.toggleSubtask(
        'f1',
        0,
        currentDate: fixedDate.add(const Duration(minutes: 1)),
      );
      expect(
        toggleOnCompleted,
        same(afterComplete),
        reason: 'Completed subtasks of a completed task must be locked and cannot be unlocked individually',
      );
      expect(
        toggleOnCompleted
            .findTask('f1')!
            .subtasks
            .every((step) => step.isCompleted),
        isTrue,
        reason: 'Attempting to toggle a subtask on a completed task must keep all subtasks completed',
      );

      final updatedCompletedInPlace = afterComplete.updateTask(
        'f1',
        subtasks: const [
          SubtaskItem(title: 'Step 1', isCompleted: true),
          SubtaskItem(title: 'Step 3', isCompleted: false),
        ],
        currentDate: fixedDate.add(const Duration(minutes: 2)),
      );
      expect(
        updatedCompletedInPlace
            .findTask('f1')!
            .subtasks
            .every((step) => step.isCompleted),
        isTrue,
        reason: 'Adding a subtask to a completed task without restoring it must immediately lock the new subtask as completed',
      );

      final afterSchedule = afterComplete.scheduleTask(
        's1',
        currentDate: fixedDate,
      );
      expect(
        afterSchedule.someday,
        isEmpty,
        reason: 'scheduleTask must remove task from Someday',
      );
      expect(
        afterSchedule.ready.map((task) => task.id),
        equals(['dep1', 's1']),
        reason: 'Scheduled Someday task must enter the active queue',
      );

      final restoredToSomeday = afterSchedule.restoreTask(
        'f1',
        targetTier: TaskTier.someday,
        currentDate: fixedDate,
      );
      expect(
        restoredToSomeday.someday.map((task) => task.id),
        equals(['f1']),
        reason: 'Restoring to Someday must clear finished and strip priority while keeping task out of queue',
      );
      expect(restoredToSomeday.queueTaskIds.contains('f1'), isFalse);
      expect(restoredToSomeday.someday.single.isPriority, isFalse);
      expect(
        restoredToSomeday.someday.single.subtasks.every(
          (step) => !step.isCompleted,
        ),
        isTrue,
        reason:
            'Restoring a completed task to Someday must reopen all subtasks',
      );

      final restoredToFocus = afterSchedule.restoreTask(
        'f1',
        targetTier: TaskTier.focus,
        currentDate: fixedDate,
      );
      expect(
        restoredToFocus.focus.first.id,
        equals('f1'),
        reason: 'Restoring to Focus must set priority and place task at the top of Focus',
      );
      expect(restoredToFocus.focus.first.isPriority, isTrue);
      expect(
        restoredToFocus.focus.first.subtasks.every((step) => !step.isCompleted),
        isTrue,
        reason: 'Restoring a completed task to Focus must reopen all subtasks',
      );

      final noopRestoreOnOpen = afterSchedule.restoreTask(
        's1',
        targetTier: TaskTier.planned,
        currentDate: fixedDate,
      );
      expect(
        noopRestoreOnOpen,
        same(afterSchedule),
        reason: 'Calling restoreTask on a non-completed task must be a no-op',
      );

      final completedPriorityAutoFinish = TaskBoard(
        completed: [
          TaskItem(
            id: 'done_prio',
            title: 'Completed Priority Auto-Finish',
            isPriority: true,
            isCompleted: true,
            createdAt: DateTime.utc(2026, 10, 20, 8, 0),
            completedAt: DateTime.utc(2026, 10, 25, 10, 0),
            subtasksAutoFinish: true,
            subtasks: const [SubtaskItem(title: 'Step 1', isCompleted: true)],
          ),
        ],
      );
      final restoreTime = DateTime.utc(2026, 11, 1, 14, 30);

      final updatedToPlanned = completedPriorityAutoFinish.updateTask(
        'done_prio',
        title: 'Completed Priority Auto-Finish',
        targetTier: TaskTier.planned,
        currentDate: restoreTime,
      );
      expect(
        updatedToPlanned.completed,
        isEmpty,
        reason: 'Restoring a completed task via updateTask (even with subtasks auto-finish all true) must remove it from Completed',
      );
      final plannedRestored = updatedToPlanned.findTask('done_prio')!;
      expect(plannedRestored.isCompleted, isFalse);
      expect(plannedRestored.completedAt, isNull);
      expect(
        plannedRestored.subtasks.every((step) => !step.isCompleted),
        isTrue,
        reason: 'Restoring to Planned via updateTask must reopen all subtasks',
      );
      expect(
        plannedRestored.isPriority,
        isFalse,
        reason: 'Restoring to Planned via updateTask must remove priority per Section 6.5',
      );
      expect(
        updatedToPlanned.queueTaskIds,
        contains('done_prio'),
        reason: 'Restoring to Planned via updateTask must append task ID to queue per Section 6.5',
      );

      final recompletedViaUpdate = updatedToPlanned.updateTask(
        'done_prio',
        title: 'Completed Priority Auto-Finish',
        targetTier: TaskTier.completed,
        currentDate: restoreTime.add(const Duration(minutes: 5)),
      );
      expect(
        recompletedViaUpdate
            .findTask('done_prio')!
            .subtasks
            .every((step) => step.isCompleted),
        isTrue,
        reason: 'Closing a task via updateTask to Completed must mark all subtasks as completed',
      );

      final updatedToFocus = completedPriorityAutoFinish.updateTask(
        'done_prio',
        title: 'Completed Priority Auto-Finish',
        targetTier: TaskTier.focus,
        isPriority: true,
        currentDate: restoreTime,
      );
      final focusRestored = updatedToFocus.findTask('done_prio')!;
      expect(focusRestored.isCompleted, isFalse);
      expect(focusRestored.completedAt, isNull);
      expect(
        focusRestored.subtasks.every((step) => !step.isCompleted),
        isTrue,
        reason: 'Restoring to Focus via updateTask must reopen all subtasks',
      );
      expect(
        focusRestored.isPriority,
        isTrue,
        reason: 'Restoring to Focus via updateTask must set priority per Section 6.5',
      );
      expect(
        updatedToFocus.queueTaskIds,
        contains('done_prio'),
        reason: 'Restoring to Focus via updateTask must append task ID to queue per Section 6.5',
      );

      final updatedToSomeday = completedPriorityAutoFinish.updateTask(
        'done_prio',
        title: 'Completed Priority Auto-Finish',
        targetTier: TaskTier.someday,
        isPriority: false,
        currentDate: restoreTime,
      );
      final somedayRestored = updatedToSomeday.findTask('done_prio')!;
      expect(somedayRestored.isCompleted, isFalse);
      expect(somedayRestored.completedAt, isNull);
      expect(
        somedayRestored.subtasks.every((step) => !step.isCompleted),
        isTrue,
        reason: 'Restoring to Someday via updateTask must reopen all subtasks',
      );
      expect(
        somedayRestored.isPriority,
        isFalse,
        reason: 'Restoring to Someday via updateTask must remove priority per Section 6.5',
      );
      expect(
        updatedToSomeday.queueTaskIds.contains('done_prio'),
        isFalse,
        reason: 'Restoring to Someday via updateTask must keep task ID out of queue per Section 6.5',
      );
    });

    test('completing a recurring task reschedules it into Blocked with priority, preserved queue position, UTC suspendedAt, advanced modifiedAt, and reset subtasks, then wakes it into Focus', () {
      final utcCompletion = DateTime.utc(2026, 11, 1, 22, 30);
      final localCompletion = DateTime.utc(2026, 11, 2, 0, 30); // UTC+2

      final recurringTask = TaskItem(
        id: 't_repeat',
        title: 'Daily routine',
        createdAt: DateTime.utc(2026, 11, 1, 8, 0),
        modifiedAt: DateTime.utc(2026, 11, 1, 8, 0),
        repeatRule: const TaskRepeatRule(count: 1, unit: RepeatUnit.days),
        subtasksAutoFinish: false,
        subtasks: const [
          SubtaskItem(title: 'Step 1', isCompleted: true),
          SubtaskItem(title: 'Step 2', isCompleted: true),
        ],
      );
      final regularTask1 = TaskItem(
        id: 't_reg1',
        title: 'Regular 1',
        createdAt: DateTime.utc(2026, 11, 1, 9, 0),
      );
      final regularTask2 = TaskItem(
        id: 't_reg2',
        title: 'Regular 2',
        createdAt: DateTime.utc(2026, 11, 1, 9, 30),
      );

      final initialBoard = TaskBoard.evaluate(
        tasks: [recurringTask, regularTask1, regularTask2],
        evaluationTime: utcCompletion,
        localEvaluationTime: localCompletion,
        queueBlock: TdfQueueBlock(
          modifiedAt: DateTime.utc(2026, 11, 1, 9, 30),
          taskIds: const <String>['t_repeat', 't_reg1', 't_reg2'],
        ),
      );

      final completedBoard = initialBoard.completeTask(
        't_repeat',
        currentDate: utcCompletion,
        localEvaluationTime: localCompletion,
      );

      expect(
        completedBoard.completed,
        isEmpty,
        reason: 'Recurring task must never enter Completed on completion',
      );
      expect(
        completedBoard.blocked.map((task) => task.id),
        equals(['t_repeat']),
        reason: 'Completed recurring task must move to Blocked (suspended)',
      );
      final rescheduled = completedBoard.findTask('t_repeat')!;
      expect(rescheduled.isCompleted, isFalse);
      expect(rescheduled.completedAt, isNull);
      expect(
        rescheduled.isPriority,
        isTrue,
        reason:
            'Recurring task must receive priority flag so it wakes into Focus',
      );
      expect(
        rescheduled.suspendedAt,
        equals(DateTime.utc(2026, 11, 2, 22, 0)),
        reason: 'localCompletion (2026-11-02 00:30) + 1 day at 00:00 local (UTC+2) must set suspendedAt to 2026-11-02 22:00 UTC per Section 6.10.3',
      );
      expect(
        completedBoard.queueTaskIds,
        equals(['t_repeat', 't_reg1', 't_reg2']),
        reason: 'Section 6.4: Recurring completion must preserve existing position in queue',
      );
      expect(
        completedBoard.queueModifiedAt,
        equals(DateTime.utc(2026, 11, 1, 9, 30)),
        reason: 'Section 6.4: Preserving existing queue position must leave queue.modified unchanged',
      );
      expect(
        rescheduled.modifiedAt,
        equals(utcCompletion),
        reason: 'modifiedAt must advance to completion UTC timestamp for sync',
      );
      expect(
        rescheduled.subtasks.every((step) => !step.isCompleted),
        isTrue,
        reason:
            'All subtasks must be reset to false for the next recurrence cycle',
      );

      final wakeUtc = DateTime.utc(2026, 11, 2, 22, 0);
      final wakeLocal = DateTime.utc(2026, 11, 3, 0, 0);
      final wokenBoard = completedBoard.applyAutoPull(
        currentDate: wakeUtc,
        localEvaluationTime: wakeLocal,
      );
      expect(
        wokenBoard.blocked,
        isEmpty,
        reason: 'Once localNow reaches suspendedAt, recurring task must leave Blocked',
      );
      expect(
        wokenBoard.focus.map((task) => task.id),
        equals(['t_repeat', 't_reg1', 't_reg2']),
        reason: 'Woken recurring task with priority must sort to the top of Focus ahead of regular tasks',
      );
    });

    test('completing a recurring task preserves explicit time-of-day on suspendedAt and clamps month-end dates', () {
      final jan31Local = DateTime.utc(2026, 1, 31, 18, 45);
      final monthlyTask = TaskItem(
        id: 't_month',
        title: 'End of month report',
        createdAt: DateTime.utc(2026, 1, 1, 8, 0),
        suspendedAt: DateTime.utc(2026, 1, 31, 9, 30),
        repeatRule: const TaskRepeatRule(
          count: 1,
          unit: RepeatUnit.months,
          clock: TdfRepeatClock(hour: 9, minute: 30),
        ),
      );

      final board = TaskBoard.evaluate(
        tasks: [monthlyTask],
        evaluationTime: jan31Local,
        queueBlock: TdfQueueBlock(
          modifiedAt: DateTime.utc(2026, 1, 1, 8, 0),
          taskIds: const <String>['t_month'],
        ),
      ).completeTask('t_month', currentDate: jan31Local);

      final rescheduled = board.findTask('t_month')!;
      expect(
        rescheduled.suspendedAt,
        equals(DateTime.utc(2026, 2, 28, 9, 30)),
        reason: '2026-01-31 + 1 month must clamp to 2026-02-28 and preserve 09:30 time of day',
      );

      final leapJan31 = DateTime.utc(2028, 1, 31, 14, 0);
      final leapTask = monthlyTask.copyWith(
        clearSuspendedAt: true,
        repeatRule: const TaskRepeatRule(count: 1, unit: RepeatUnit.months),
      );
      final leapBoard = TaskBoard.evaluate(
        tasks: [leapTask],
        evaluationTime: leapJan31,
        queueBlock: TdfQueueBlock(
          modifiedAt: DateTime.utc(2026, 1, 1, 8, 0),
          taskIds: const <String>['t_month'],
        ),
      ).completeTask('t_month', currentDate: leapJan31);
      expect(
        leapBoard.findTask('t_month')!.suspendedAt,
        equals(DateTime.utc(2028, 2, 29, 0, 0)),
        reason:
            '2028-01-31 + 1 month in leap year must clamp to 2028-02-29 00:00',
      );
    });

    test('completes TDF 0.6.0 standard task preserving dueAt and origin, and completes Mode 2 recurring task with dueAt advancing dueAt and suspendedAt along fixed schedule', () {
      const origin = TaskOrigin(namespace: 'jira', externalKey: 'OPS-42');
      final dueTime = DateTime.utc(2026, 3, 28, 16, 0);
      final standardTask = TaskItem(
        id: 'tStdDue001',
        title: 'Standard Task With Due and Origin',
        createdAt: DateTime.utc(2026, 3, 20, 8, 0),
        dueAt: dueTime,
        origin: origin,
      );
      final recurringDueTask = TaskItem(
        id: 'tRecDue001',
        title: 'Mode 2 Recurring Task With Lead Window',
        createdAt: DateTime.utc(2026, 3, 20, 8, 0),
        suspendedAt: DateTime.utc(2026, 3, 26, 8, 0),
        dueAt: dueTime,
        origin: origin,
        repeatRule: const TaskRepeatRule(
          count: 1,
          unit: RepeatUnit.weeks,
          clock: TdfRepeatClock(hour: 9, minute: 0),
          leadDays: 2,
        ),
      );

      const berlinZone = TdfTimeZoneContext.europeBerlin;
      final completionUtc = DateTime.utc(2026, 3, 28, 10, 0);
      final completionLocal = berlinZone.toLocalWallClock(completionUtc);

      var board = TaskBoard.evaluate(
        tasks: [standardTask, recurringDueTask],
        evaluationTime: completionUtc,
        localEvaluationTime: completionLocal,
        timeZone: berlinZone,
        queueBlock: TdfQueueBlock(
          modifiedAt: DateTime.utc(2026, 3, 20, 8, 0),
          taskIds: const ['tStdDue001', 'tRecDue001'],
        ),
      );

      board = board.completeTask(
        'tStdDue001',
        currentDate: completionUtc,
        localEvaluationTime: completionLocal,
        timeZone: berlinZone,
      );
      final completedStd = board.findTask('tStdDue001')!;
      expect(completedStd.isCompleted, isTrue);
      expect(
        completedStd.dueAt,
        equals(dueTime),
        reason:
            'Section 6.4: Standard completion must preserve dueAt unchanged',
      );
      expect(
        completedStd.origin,
        equals(origin),
        reason:
            'Section 6.4: Standard completion must preserve origin unchanged',
      );

      board = board.completeTask(
        'tRecDue001',
        currentDate: completionUtc,
        localEvaluationTime: completionLocal,
        timeZone: berlinZone,
      );
      final rescheduled = board.findTask('tRecDue001')!;
      expect(rescheduled.isCompleted, isFalse);
      expect(rescheduled.completions, equals(1));
      expect(rescheduled.origin, equals(origin));
      expect(
        rescheduled.dueAt,
        equals(DateTime.utc(2026, 4, 4, 15, 0)),
        reason: 'Section 6.4 & 6.10.3: Mode 2 must advance due to 2026-04-04 17:00 CEST (15:00 UTC)',
      );
      expect(
        rescheduled.suspendedAt,
        equals(DateTime.utc(2026, 4, 2, 7, 0)),
        reason: 'Section 6.4 & 6.10.3: Mode 2 must preserve 2-day local calendar lead window to 2026-04-02 09:00 CEST (07:00 UTC)',
      );
    });
  });

  group('TDF 0.7.0 Lifecycle Rules: Completion, Mode 2 Lead Omission, Restore & Dependent Cleanup', () {
    test('completes standard and Mode 2 recurring tasks with leadDays, omits already-elapsed newSuspendedUtc, cleans open dependents, and clears due/suspended notes on restore', () {
      final now = DateTime.utc(2026, 11, 5, 14, 0, 0);
      final prereq = TaskItem(
        id: 'stdPrereq1',
        title: 'Standard Prereq With Passive Due And History',
        createdAt: now.subtract(const Duration(days: 2)),
        modifiedAt: now.subtract(const Duration(days: 1)),
        dueAt: now.add(const Duration(hours: 4)),
        isDuePassive: true,
        dueNote: 'Regulatory filing deadline',
        origin: const TaskOrigin(namespace: 'ext', externalKey: '42'),
        history: <TaskHistoryEntry>[
          TaskHistoryEntry(
            timestampUtc: now.subtract(const Duration(days: 1)),
            text: 'Draft prepared',
          ),
        ],
      );
      final openDependent = TaskItem(
        id: 'openDep001',
        title: 'Open Dependent Unblocked When Prereq Completes',
        createdAt: now.subtract(const Duration(days: 2)),
        modifiedAt: now.subtract(const Duration(days: 1)),
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'stdPrereq1', requiredCompletion: 1),
        ],
      );
      // Mode 2 recurring task whose next due is tomorrow 18:00 UTC, with leadDays: 2 -> newSuspendedUtc is yesterday 09:00 UTC <= now!
      final mode2ActiveImmediately = TaskItem(
        id: 'recImmed01',
        title: 'Mode 2 Recurring Task Entering Active Lead Window Immediately',
        createdAt: now.subtract(const Duration(days: 10)),
        modifiedAt: now.subtract(const Duration(days: 1)),
        suspendedAt: now.subtract(const Duration(days: 2)),
        suspendedNote: 'One-off deferral note cleared on cycle',
        dueAt: DateTime.utc(2026, 11, 5, 18, 0, 0),
        isDuePassive: true,
        dueNote: 'Recurring SLA note preserved across cycle',
        repeatRule: const TaskRepeatRule(
          count: 1,
          unit: RepeatUnit.days,
          clock: TdfRepeatClock(hour: 9, minute: 0),
          leadDays: 2,
        ),
        history: <TaskHistoryEntry>[
          TaskHistoryEntry(
            timestampUtc: now.subtract(const Duration(days: 3)),
            text: 'Previous cycle note',
          ),
        ],
      );

      var board = TaskBoard.evaluate(
        tasks: <TaskItem>[prereq, openDependent, mode2ActiveImmediately],
        evaluationTime: now,
        timeZone: TdfTimeZoneContext.utc,
        queueBlock: TdfQueueBlock(
          modifiedAt: now.subtract(const Duration(days: 1)),
          taskIds: const <String>['stdPrereq1', 'openDep001', 'recImmed01'],
        ),
      );
      expect(board.blocked.map((t) => t.id), contains('openDep001'));

      // Complete standard prerequisite -> openDep001 has its satisfied non-recurring blocked directive stripped immediately!
      board = board.completeTask(
        'stdPrereq1',
        currentDate: now,
        timeZone: TdfTimeZoneContext.utc,
      );
      final donePrereq = board.findTask('stdPrereq1')!;
      expect(donePrereq.isCompleted, isTrue);
      expect(donePrereq.dueAt, equals(prereq.dueAt));
      expect(donePrereq.isDuePassive, isTrue);
      expect(donePrereq.dueNote, equals('Regulatory filing deadline'));
      expect(donePrereq.history.length, equals(1));
      expect(
        board.findTask('openDep001')!.dependencies,
        isEmpty,
        reason: 'Completing a non-recurring prerequisite must immediately strip resolved blocked directives on open dependents',
      );
      expect(board.focus.map((t) => t.id), contains('openDep001'));

      // Complete Mode 2 task -> newDue is 2026-11-06 18:00 UTC, newSuspended is 2026-11-04 09:00 UTC <= now, so suspendedAt is omitted (null)!
      board = board.completeTask(
        'recImmed01',
        currentDate: now,
        timeZone: TdfTimeZoneContext.utc,
      );
      final cycled = board.findTask('recImmed01')!;
      expect(cycled.isCompleted, isFalse);
      expect(cycled.completions, equals(1));
      expect(cycled.dueAt, equals(DateTime.utc(2026, 11, 6, 18, 0, 0)));
      expect(
        cycled.suspendedAt,
        isNull,
        reason: 'Section 6.4 Mode 2: when newSuspendedUtc <= now, suspended must be omitted so the task enters active tiers immediately',
      );
      expect(cycled.suspendedNote, isNull);
      expect(
        cycled.isDuePassive,
        isFalse,
        reason: 'Section 6.4 Mode 2: advancing to a new cycle due date must reset isDuePassive to false',
      );
      expect(
        cycled.dueNote,
        equals('Recurring SLA note preserved across cycle'),
      );
      expect(cycled.history.length, equals(1));
      expect(board.focus.map((t) => t.id), contains('recImmed01'));

      // Restore completed task -> clears finished, dueAt, isDuePassive, dueNote, suspended, suspendedNote while preserving history & origin:
      board = board.restoreTask(
        'stdPrereq1',
        targetTier: TaskTier.planned,
        currentDate: now.add(const Duration(minutes: 5)),
      );
      final restored = board.findTask('stdPrereq1')!;
      expect(restored.isCompleted, isFalse);
      expect(restored.completedAt, isNull);
      expect(restored.dueAt, isNull);
      expect(restored.isDuePassive, isFalse);
      expect(restored.dueNote, isNull);
      expect(restored.suspendedAt, isNull);
      expect(restored.suspendedNote, isNull);
      expect(restored.origin, equals(prereq.origin));
      expect(restored.history.length, equals(1));

      // Full-capacity canonical task (500 history + 20 links + all scalars + condition + subtasks) completes cleanly under 1024 limit:
      final maxTask = TaskItem(
        id: 'maxCapOpen',
        title: 'Full Capacity Open Task',
        note: 'Body note',
        createdAt: now,
        modifiedAt: now,
        completions: 1,
        labelIds: const <String>['lblWork001'],
        suspendedAt: now.add(const Duration(hours: 1)),
        suspendedNote: 'Susp note',
        dueAt: now.add(const Duration(hours: 5)),
        isDuePassive: true,
        dueNote: 'Due note',
        origin: const TaskOrigin(namespace: 'ns', externalKey: 'k'),
        links: <TaskLink>[
          for (var i = 0; i < TaskLink.maxLinksPerTask; i++)
            TaskLink(title: 'L$i', uri: 'https://example.com/$i'),
        ],
        history: <TaskHistoryEntry>[
          for (var i = 0; i < maxTdfHistoryPerTask; i++)
            TaskHistoryEntry(
              timestampUtc: now.add(Duration(seconds: i)),
              text: 'H$i',
            ),
        ],
        conditions: const <TaskCondition>[GlobalResetTaskCondition()],
        subtasks: const <SubtaskItem>[SubtaskItem(title: 'Step')],
      );
      final maxBoard = TaskBoard.evaluate(
        tasks: <TaskItem>[maxTask],
        labels: const <TdfLabel>[TdfLabel(id: 'lblWork001', name: 'Work')],
        evaluationTime: now,
      );
      final completedMaxBoard = maxBoard.completeTask(
        'maxCapOpen',
        currentDate: now.add(const Duration(minutes: 10)),
      );
      expect(completedMaxBoard.findTask('maxCapOpen')!.isCompleted, isTrue);
      expect(
        completedMaxBoard.findTask('maxCapOpen')!.history.length,
        equals(500),
      );
    });

    test('scheduleTask resets isDuePassive on explicit priority promotion (Section 6.2) and clears due on completed task scheduling (Section 6.5)', () {
      final t0 = DateTime.utc(2026, 11, 15, 9, 0);
      final dueTime = DateTime.utc(2026, 11, 16, 8, 0);
      var board = TaskBoard.empty().addTask(
        'Someday Passive Task',
        targetTier: TaskTier.someday,
        dueAt: dueTime,
        isDuePassive: true,
        dueNote: 'Informational',
        currentDate: t0,
      );
      final somedayId = board.someday.single.id;

      // Scheduling without priority preserves isDuePassive == true:
      final t1 = t0.add(const Duration(minutes: 5));
      board = board.scheduleTask(somedayId, isPriority: false, currentDate: t1);
      expect(
        board.findTask(somedayId)!.isDuePassive,
        isTrue,
        reason: 'Non-priority scheduleTask must preserve passive flag',
      );

      // Explicit scheduleTask(isPriority: true) resets isDuePassive to false and advances modifiedAt:
      final t2 = t1.add(const Duration(minutes: 5));
      board = board.scheduleTask(somedayId, isPriority: true, currentDate: t2);
      final promoted = board.findTask(somedayId)!;
      expect(promoted.isPriority, isTrue);
      expect(
        promoted.isDuePassive,
        isFalse,
        reason: 'Section 6.2: scheduleTask with isPriority: true must reset passive to false',
      );
      expect(promoted.dueAt, equals(dueTime));
      expect(promoted.dueNote, equals('Informational'));
      expect(promoted.effectiveModifiedAt, equals(t2));

      // Even if a task already has isPriority: true and isDuePassive: true, scheduleTask(isPriority: true) resets passive:
      final t3 = t2.add(const Duration(minutes: 5));
      board = board.updateTask(
        somedayId,
        isPriority: true,
        isDuePassive: true,
        currentDate: t3,
      );
      expect(board.findTask(somedayId)!.isDuePassive, isTrue);
      final t4 = t3.add(const Duration(minutes: 5));
      board = board.scheduleTask(somedayId, isPriority: true, currentDate: t4);
      expect(
        board.findTask(somedayId)!.isDuePassive,
        isFalse,
        reason: 'Explicit priority scheduleTask must reset passive even when already priority',
      );
      expect(board.findTask(somedayId)!.effectiveModifiedAt, equals(t4));

      // Scheduling a completed task clears dueAt, dueNote, and isDuePassive (Section 6.5):
      final t5 = t4.add(const Duration(minutes: 5));
      board = board.completeTask(somedayId, currentDate: t5);
      expect(board.findTask(somedayId)!.dueAt, equals(dueTime));
      final t6 = t5.add(const Duration(minutes: 5));
      board = board.scheduleTask(somedayId, isPriority: false, currentDate: t6);
      final rescheduledCompleted = board.findTask(somedayId)!;
      expect(rescheduledCompleted.isCompleted, isFalse);
      expect(
        rescheduledCompleted.dueAt,
        isNull,
        reason: 'Scheduling a completed task must clear dueAt per Section 6.5',
      );
      expect(rescheduledCompleted.dueNote, isNull);
      expect(rescheduledCompleted.isDuePassive, isFalse);
    });

    test('TDF 0.8.0 restoreTask clears dueAt, dueAnchor, isDuePassive, and dueNote across Someday/Planned/Focus while scheduleTask preserves dueAnchor on Someday', () {
      final t0 = DateTime.utc(2026, 1, 31, 9, 0);
      final anchor = TdfLocalDateTime(2026, 1, 31, 18, 0, 0);
      final openPrereq = TaskItem(
        id: 'openPre001',
        title: 'Open Prerequisite',
        completions: 2,
        createdAt: t0,
      );
      final completedAnchored = TaskItem(
        id: 'doneAnc001',
        title: 'Completed With Schedule Anchor',
        isCompleted: true,
        completedAt: t0,
        modifiedAt: t0,
        completions: 5,
        isPriority: true,
        suspendedAt: t0.add(const Duration(days: 2)),
        suspendedNote: 'Old snooze',
        dueAt: DateTime.utc(2026, 1, 31, 17, 0, 0),
        dueAnchor: anchor,
        isDuePassive: true,
        dueNote: 'Old SLA note',
        origin: const TaskOrigin(namespace: 'jira', externalKey: 'OPS-7'),
        repeatRule: const TaskRepeatRule(
          count: 1,
          unit: RepeatUnit.months,
          clock: TdfRepeatClock(hour: 8, minute: 30),
          leadDays: 3,
        ),
        dependencies: const <TdfTaskDependency>[
          TdfTaskDependency(taskId: 'openPre001', requiredCompletion: 1),
        ],
        history: <TaskHistoryEntry>[
          TaskHistoryEntry(timestampUtc: t0, text: 'Filed report'),
        ],
        subtasks: const <SubtaskItem>[
          SubtaskItem(title: 'Verify totals', isCompleted: true),
        ],
      );

      final board = TaskBoard.evaluate(
        tasks: <TaskItem>[openPrereq, completedAnchored],
        queueBlock: TdfQueueBlock(
          modifiedAt: t0,
          taskIds: const <String>['openPre001'],
        ),
        evaluationTime: t0,
      );
      expect(board.findTask('doneAnc001')!.dueAnchor, equals(anchor));

      // Invalid restore target tiers (ready, blocked, completed) are pure no-ops:
      final t1 = t0.add(const Duration(minutes: 5));
      expect(
        board.restoreTask(
          'doneAnc001',
          targetTier: TaskTier.ready,
          currentDate: t1,
        ),
        same(board),
      );
      expect(
        board.restoreTask(
          'doneAnc001',
          targetTier: TaskTier.blocked,
          currentDate: t1,
        ),
        same(board),
      );

      for (final target in const <TaskTier>[
        TaskTier.someday,
        TaskTier.planned,
        TaskTier.focus,
      ]) {
        final restoredBoard = board.restoreTask(
          'doneAnc001',
          targetTier: target,
          currentDate: t1,
        );
        final restored = restoredBoard.findTask('doneAnc001')!;
        expect(restored.isCompleted, isFalse, reason: 'target=$target');
        expect(restored.completedAt, isNull, reason: 'target=$target');
        expect(restored.dueAt, isNull, reason: 'target=$target');
        expect(
          restored.dueAnchor,
          isNull,
          reason: 'TDF-MUT-007: restoreTask must clear dueAnchor ($target)',
        );
        expect(restored.isDuePassive, isFalse, reason: 'target=$target');
        expect(restored.dueNote, isNull, reason: 'target=$target');
        expect(restored.suspendedAt, isNull, reason: 'target=$target');
        expect(restored.isSuspendedForever, isFalse, reason: 'target=$target');
        expect(restored.suspendedNote, isNull, reason: 'target=$target');
        expect(restored.completions, equals(5), reason: 'target=$target');
        expect(
          restored.repeatRule,
          equals(completedAnchored.repeatRule),
          reason: 'target=$target',
        );
        expect(
          restored.origin,
          equals(completedAnchored.origin),
          reason: 'target=$target',
        );
        expect(
          restored.history,
          equals(completedAnchored.history),
          reason: 'target=$target',
        );
        expect(
          restored.subtasks.single.isCompleted,
          isFalse,
          reason: 'target=$target',
        );
        expect(
          restored.dependencies.single.requiredCompletion,
          equals(3),
          reason: 'TDF-OCC-001: prerequisite must rearm to 2 + 1 = 3',
        );
      }

      // scheduleTask from Someday preserves dueAnchor (and resets passive on priority = true):
      var someBoard = TaskBoard.empty().addTask(
        'Anchored Someday',
        id: 'ancSome001',
        targetTier: TaskTier.someday,
        dueAt: DateTime.utc(2026, 2, 28, 17, 0, 0),
        dueAnchor: anchor,
        isDuePassive: true,
        dueNote: 'Carry anchor',
        currentDate: t0,
      );
      someBoard = someBoard.scheduleTask(
        'ancSome001',
        isPriority: false,
        currentDate: t1,
      );
      expect(someBoard.findTask('ancSome001')!.dueAnchor, equals(anchor));
      expect(someBoard.findTask('ancSome001')!.isDuePassive, isTrue);

      final t2 = t1.add(const Duration(minutes: 5));
      someBoard = someBoard.scheduleTask(
        'ancSome001',
        isPriority: true,
        currentDate: t2,
      );
      expect(someBoard.findTask('ancSome001')!.dueAnchor, equals(anchor));
      expect(someBoard.findTask('ancSome001')!.isDuePassive, isFalse);
    });
  });
}
