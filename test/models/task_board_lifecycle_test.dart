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
      expect(serialized, contains('step true "Verify regression tests"'));

      final reparsed = tdfService.parse(serialized, evaluationTime: fixedDate);
      expect(
        reparsed.focus.first.subtasks.map((subtask) => subtask.title),
        equals(['Patch vulnerability', 'Verify regression tests']),
      );
    });

    test('completes enclosing task automatically when subtasks has auto-finish and all steps become true', () {
      const autoFinishTdf = '''
tdf 0.4.0

task auto00OkD2 {
    name "Auto-finish task"
    created 2026-11-01 09:00
    queued 2026-11-01 09:00
    subtasks auto-finish {
        step true "Step 1"
        step false "Step 2"
    }
}
task manualOkD2 {
    name "Manual finish task"
    created 2026-11-01 09:05
    queued 2026-11-01 09:05
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
          TaskItem(id: 'f1', title: 'Finish spec'),
          TaskItem(id: 'f2', title: 'Task 2'),
          TaskItem(id: 'f3', title: 'Task 3'),
        ],
        ready: [TaskItem(id: 'b1', title: 'Ready 1')],
        blocked: [
          TaskItem(
            id: 'dep1',
            title: 'Waiting on f1',
            queuedAt: DateTime.utc(2026, 11, 1, 9, 0),
            blockedByTaskIds: const ['f1'],
          ),
        ],
        someday: [TaskItem(id: 's1', title: 'Someday Idea')],
        completed: [
          TaskItem(
            id: 'e_keep_29',
            title: '29 Days Ago',
            isCompleted: true,
            completedAt: DateTime.utc(2026, 10, 3),
          ),
          TaskItem(
            id: 'e_keep_30',
            title: '30 Days Ago',
            isCompleted: true,
            completedAt: DateTime.utc(2026, 10, 2),
          ),
          TaskItem(
            id: 'e_prune_31',
            title: '31 Days Ago',
            isCompleted: true,
            completedAt: DateTime.utc(2026, 10, 1),
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
        reason: 'Restoring to Someday must clear finished and queued and strip priority',
      );
      expect(restoredToSomeday.someday.single.queuedAt, isNull);
      expect(restoredToSomeday.someday.single.isPriority, isFalse);

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
            queuedAt: DateTime.utc(2026, 10, 20, 8, 0),
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
        plannedRestored.isPriority,
        isFalse,
        reason: 'Restoring to Planned via updateTask must remove priority per Section 6.5',
      );
      expect(
        plannedRestored.queuedAt,
        equals(restoreTime),
        reason: 'Restoring to Planned via updateTask must replace the old queued timestamp with now per Section 6.5',
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
        focusRestored.isPriority,
        isTrue,
        reason: 'Restoring to Focus via updateTask must set priority per Section 6.5',
      );
      expect(
        focusRestored.queuedAt,
        equals(restoreTime),
        reason: 'Restoring to Focus via updateTask must replace the old queued timestamp with now per Section 6.5',
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
        somedayRestored.isPriority,
        isFalse,
        reason: 'Restoring to Someday via updateTask must remove priority per Section 6.5',
      );
      expect(
        somedayRestored.queuedAt,
        isNull,
        reason: 'Restoring to Someday via updateTask must omit queued per Section 6.5',
      );
    });

    test('completing a recurring task reschedules it into Blocked with priority, UTC queuedAt, local suspendedAt, advanced modifiedAt, and reset subtasks, then wakes it into Focus', () {
      final utcCompletion = DateTime.utc(2026, 11, 1, 22, 30);
      final localCompletion = DateTime.utc(2026, 11, 2, 0, 30); // UTC+2

      final recurringTask = TaskItem(
        id: 't_repeat',
        title: 'Daily routine',
        createdAt: DateTime.utc(2026, 11, 1, 8, 0),
        queuedAt: DateTime.utc(2026, 11, 1, 8, 0),
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
        queuedAt: DateTime.utc(2026, 11, 1, 9, 0),
      );
      final regularTask2 = TaskItem(
        id: 't_reg2',
        title: 'Regular 2',
        createdAt: DateTime.utc(2026, 11, 1, 9, 30),
        queuedAt: DateTime.utc(2026, 11, 1, 9, 30),
      );

      final initialBoard = TaskBoard.evaluate(
        tasks: [recurringTask, regularTask1, regularTask2],
        evaluationTime: utcCompletion,
        localEvaluationTime: localCompletion,
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
        equals(DateTime.utc(2026, 11, 3, 0, 0)),
        reason: 'localCompletion (2026-11-02 00:30) + 1 day must set suspendedAt to 2026-11-03 00:00 local time',
      );
      expect(
        rescheduled.queuedAt,
        equals(DateTime.utc(2026, 11, 2, 22, 0)),
        reason: 'queuedAt must be converted from 2026-11-03 00:00 local (UTC+2) to 2026-11-02 22:00 UTC',
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
        queuedAt: DateTime.utc(2026, 1, 1, 8, 0),
        suspendedAt: DateTime.utc(2026, 1, 31, 9, 30),
        repeatRule: const TaskRepeatRule(count: 1, unit: RepeatUnit.months),
      );

      final board = TaskBoard.evaluate(
        tasks: [monthlyTask],
        evaluationTime: jan31Local,
      ).completeTask('t_month', currentDate: jan31Local);

      final rescheduled = board.findTask('t_month')!;
      expect(
        rescheduled.suspendedAt,
        equals(DateTime.utc(2026, 2, 28, 9, 30)),
        reason: '2026-01-31 + 1 month must clamp to 2026-02-28 and preserve 09:30 time of day',
      );

      final leapJan31 = DateTime.utc(2028, 1, 31, 14, 0);
      final leapTask = monthlyTask.copyWith(clearSuspendedAt: true);
      final leapBoard = TaskBoard.evaluate(
        tasks: [leapTask],
        evaluationTime: leapJan31,
      ).completeTask('t_month', currentDate: leapJan31);
      expect(
        leapBoard.findTask('t_month')!.suspendedAt,
        equals(DateTime.utc(2028, 2, 29, 0, 0)),
        reason:
            '2028-01-31 + 1 month in leap year must clamp to 2028-02-29 00:00',
      );
    });
  });
}
