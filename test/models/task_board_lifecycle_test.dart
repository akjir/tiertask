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

  group(
    'TDF Section 6 State Transitions, Subtasks Auto-Finish & Retention GC',
    () {
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
          id: 't001',
        );
        board = board.addTask(
          'Task 2',
          targetTier: TaskTier.planned,
          currentDate: DateTime.utc(2026, 11, 1, 8, 5),
          id: 't002',
        );
        board = board.addTask(
          'Task 3',
          targetTier: TaskTier.planned,
          currentDate: DateTime.utc(2026, 11, 1, 8, 10),
          id: 't003',
        );

        expect(
          board.focus.map((task) => task.id),
          equals(['t001', 't002', 't003']),
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
          id: 't004',
        );

        expect(
          updated.focus.map((task) => task.id),
          equals(['t004', 't001', 't002']),
          reason: 'Priority task must sort to the top of Focus and push 3rd task to Ready',
        );
        expect(updated.ready.map((task) => task.id), equals(['t003']));

        final serialized = tdfService.serialize(updated);
        expect(serialized, contains('task t004 priority {'));
        expect(serialized, contains('subtasks auto-finish {'));
        expect(serialized, contains('step false "Patch vulnerability"'));
        expect(serialized, contains('step true "Verify regression tests"'));

        final reparsed = tdfService.parse(
          serialized,
          evaluationTime: fixedDate,
        );
        expect(
          reparsed.focus.first.subtasks.map((subtask) => subtask.title),
          equals(['Patch vulnerability', 'Verify regression tests']),
        );
      });

      test('completes enclosing task automatically when subtasks has auto-finish and all steps become true', () {
        const autoFinishTdf = '''
tdf 0.2.0

task t_auto {
    name "Auto-finish task"
    created 2026-11-01 09:00
    queued 2026-11-01 09:00
    subtasks auto-finish {
        step true "Step 1"
        step false "Step 2"
    }
}
task t_manual {
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
          equals(['t_auto', 't_manual']),
        );

        board = board.toggleSubtask('t_auto', 1, currentDate: fixedDate);
        expect(
          board.completed.map((task) => task.id),
          equals(['t_auto']),
          reason: 'Completing all steps in subtasks auto-finish must transition task to Completed',
        );
        expect(board.focus.map((task) => task.id), equals(['t_manual']));

        board = board.toggleSubtask('t_manual', 1, currentDate: fixedDate);
        expect(
          board.focus.map((task) => task.id),
          equals(['t_manual']),
          reason:
              'Completing all steps without auto-finish must keep task open',
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
    },
  );
}
